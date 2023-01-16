
    #!/bin/bash
    agentuser=${AGENT_USER}
    pool=${AGENT_POOL}
    pat=${AGENT_TOKEN}
    azdourl=${AZDO_URL}
    
    # install az cli
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    
    # install docker
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
    sudo apt update
    sudo apt install -y docker-ce
    sudo usermod -aG docker $agentuser
    
    # install kubectl
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
    sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
    sudo apt update
    sudo apt-get install -y kubectl

    # install kubelogin
    sudo apt-get install git-all
    (
        set -x; cd "$(mktemp -d)" &&
        OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
        ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
        KREW="krew-${OS}_${ARCH}" &&
        curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
        tar zxvf "${KREW}.tar.gz" &&
        ./"${KREW}" install krew
    )
    export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
    kubectl krew install oidc-login

    # install kubelogin using Homebrew
    #/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    #echo '# Set PATH, MANPATH, etc., for Homebrew.' >> /home/$agentuser/.profile
    #echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /home/$agentuser/.profile
    #eval "$(/opt/homebrew/bin/brew shellenv)"
    #sudo brew install int128/kubelogin/kubelogin

    # install helm
    curl -o helm.tar.gz https://get.helm.sh/helm-v3.3.4-linux-amd64.tar.gz
    tar zxvf helm.tar.gz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    rm -rf linux-amd64
    rm -f helm.tar.gz
    
    # download azdo agent
    sudo mkdir -p /opt/azdo && cd /opt/azdo
    sudo curl -o azdoagent.tar.gz https://vstsagentpackage.azureedge.net/agent/2.214.1/vsts-agent-linux-x64-2.214.1.tar.gz
    sudo tar xzvf azdoagent.tar.gz
    sudo rm -f azdoagent.tar.gz
    
    # configure as azdouser
    sudo chown -R $agentuser /opt/azdo
    sudo chmod -R 755 /opt/azdo
    sudo runuser -l $agentuser -c "/opt/azdo/config.sh --unattended --url $azdourl --auth pat --token $pat --pool $pool --acceptTeeEula"
    
    # install and start the service
    sudo ./svc.sh install
    sudo ./svc.sh start