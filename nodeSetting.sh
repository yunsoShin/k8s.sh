#!/bin/bash

# OS 확인
OS="$(uname -s)"
if [ "$OS" == "Linux" ]; then
    # IP 주소 가져오기
    MASTER_IP=$(hostname -I | awk '{print $1}')
    if ! command -v socat &> /dev/null; then
        echo "socat이 설치되어 있지 않습니다. 설치를 진행합니다..."
        sudo apt-get update
        sudo apt-get install -y socat
        echo "socat 설치 완료"
    else
        echo "socat이 이미 설치되어 있습니다."
    fi
    # 사용자 입력 받기
    read -p "Master(M) 또는 Worker(W) 노드를 설정하시겠습니까? (M/W): " NODE_TYPE

    if [ "$NODE_TYPE" == "M" ]; then
        echo "Master 노드를 설정합니다. IP 주소: $MASTER_IP"

        # kubeadm init 실행
        sudo kubeadm init --apiserver-advertise-address $MASTER_IP

        if [ $? -eq 0 ]; then
            echo "Kubeadm 초기화 완료. 클러스터 정보를 확인합니다..."

            # 유저가 루트가 아닌 경우 설정
            if [ "$EUID" -ne 0 ]; then
                echo "루트 유저가 아니므로, 현재 사용자에 대해 kubeconfig를 설정합니다..."
                mkdir -p $HOME/.kube
                sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
                sudo chown $(id -u):$(id -g) $HOME/.kube/config
                echo "kubeconfig 설정 완료"
            else
                echo "루트 유저입니다. KUBECONFIG 환경 변수를 설정합니다..."
                export KUBECONFIG=/etc/kubernetes/admin.conf
            fi

            # 클러스터 정보 확인
            kubectl cluster-info

            # 노드 상태 확인
            kubectl get nodes

            # Calico 네트워크 플러그인 설치
            echo "Calico 네트워크 플러그인을 설치합니다..."
            kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml

            # 설치된 Pod 상태 확인
            echo "Calico 설치 후, kube-system 네임스페이스에서 Pod 상태를 확인합니다."
            kubectl -n kube-system get pod

            echo "Master 노드 구성이 완료되었습니다."

            # 워커 노드에 제공할 조인 명령어 생성
            echo "워커 노드를 위한 조인 명령어를 생성합니다..."
            JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
            echo "워커 노드는 다음 명령어로 마스터 노드에 조인할 수 있습니다:"
            echo "$JOIN_COMMAND"
        else
            echo "Kubeadm 초기화 중 오류가 발생했습니다."
            exit 1
        fi

    elif [ "$NODE_TYPE" == "W" ]; then
        echo "Worker 노드를 설정합니다."

        # 토큰 입력 받기
        read -p "마스터 노드에서 생성된 토큰을 입력하세요: " TOKEN

        # hash 값 입력 받기
        read -p "마스터 노드에서 제공된 discovery-token-ca-cert-hash 값을 입력하세요 (sha256:로 시작하는 값): " HASH

        # 마스터 노드 IP 입력 받기
        read -p "마스터 노드의 IP 주소를 입력하세요: " MASTER_IP

        # 워커 노드 조인 명령 실행
        sudo kubeadm join $MASTER_IP:6443 --token $TOKEN --discovery-token-ca-cert-hash $HASH

        if [ $? -eq 0 ]; then
            echo "Worker 노드가 마스터 노드에 성공적으로 조인되었습니다."
        else
            echo "Worker 노드 조인 중 오류가 발생했습니다."
            exit 1
        fi

    else
        echo "잘못된 입력입니다. M 또는 W를 입력해 주세요."
        exit 1
    fi
else
    echo "지원되지 않는 운영체제입니다."
    exit 1
fi
