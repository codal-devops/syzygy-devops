# K8S Bare Metal Setup Steps

> ## Steps to configure k8s environment on Ubuntu based on-premise or cloud server.

- Make both scripts executable with `chmod a+x base.sh && chmod a+x service.sh`.
- Run command `sudo su -c /home/ubuntu/syzygy-devops/base.sh root`. This will install all docker and k8s dependencies on your machine.
- Run command `bash service.sh`. This will setup all services for your application.
- If you want to run as "One Time Script" then run command:
    `sudo su -c /home/ubuntu/accis-devops/base.sh root && bash service.sh`
