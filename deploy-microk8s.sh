#!/bin/bash

# install
sudo snap install microk8s --classic --channel=1.30

# join group
sudo usermod -a -G microk8s $USER
mkdir -p ~/.kube
chmod 0700 ~/.kube
su - $USER
alias kubectl='microk8s kubectl'
sudo snap alias microk8s.kubectl kubectl

#sudo microk8s enable kube-ovn
#microk8s enable kube-ovn --force
sudo microk8s enable dns
sudo microk8s enable ingress
sudo microk8s enable hostpath-storage
sudo microk8s enable rbac
sudo microk8s enable community
sudo microk8s enable nfs

#!/bin/bash

echo "Is this a master node? (y/n)"
read answer
# Check the user's input
if [[ "$answer" == "y" ]]; then
    # If this is the main node, offer to add new nodes in a loop
    while true; do
        echo "Adding a new node..."
        microk8s add-node

        # Ask if the user is done adding nodes
        echo "Are you done adding nodes? If yes, type 'done', otherwise press enter to continue adding nodes."
        read imdone

        if [[ "$imdone" == "done" ]]; then
            echo "Finished adding nodes."
            break
        fi
    done
    sudo microk8s enable portainer
elif [[ "$answer" == "n" ]]; then
    # If this is not the main node, ask for the command to join the master
    echo "Please enter the command to join the master:"
    read join_command
    echo "Joining the master..."
    eval "$join_command"
else
    echo "Invalid input. Please enter 'y' or 'n'."
fi

microk8s kubectl get pods -n portainer
microk8s kubectl get all -n portainer
microk8s kubectl get serviceaccounts -n portainer
microk8s kubectl rollout restart deployment -n portainer

export NODE_PORT=$(kubectl get --namespace portainer -o jsonpath="{.spec.ports[1].nodePort}" services portainer)
export NODE_IP=$(kubectl get nodes --namespace portainer -o jsonpath="{.items[0].status.addresses[0].address}")
echo Portainer is available on https://$NODE_IP:$NODE_PORT Use the Nodeport or LB port to access.

