#!/bin/bash

## PostgreSQL Installation 

sudo apt update -y

sudo apt install postgresql postgresql-contrib -y

echo "$(tput bold)$(tput setaf 4)Welcome to Syzygy Setup: PostgreSQL Database Installation.$(tput sgr 0)"

set -e
echo "Enter the Database Name: "
read pg_dbname
var2=`echo -n $pg_dbname | base64`

echo "Enter the Database User Name: "
read pg_user
var3=`echo -n $pg_user | base64`

echo "Enter the Database Password: "
read pg_pwd
var4=`echo -n $pg_pwd | base64`

sudo su postgres <<EOF
createdb  $pg_dbname;
psql -c "CREATE USER $pg_user WITH PASSWORD '$pg_pwd';"
psql -c "grant all privileges on database $pg_dbname to $pg_user;"
echo "Postgres User '$pg_user' and database '$pg_dbname' created."
EOF

sudo sed -i "s/#listen_addresses = 'localhost'*/listen_addresses = '*'/g" /etc/postgresql/12/main/postgresql.conf
sudo sed -i 's~127.0.0.1/32~0.0.0.0/0~g' /etc/postgresql/12/main/pg_hba.conf
sudo systemctl restart postgresql.service


## Setting up environment variables

echo "$(tput bold)$(tput setaf 4)Welcome to Syzygy Setup: Let's get your environment ready..!!$(tput sgr 0)"

echo "Server Hostname:"
hostname
var7=`echo -n $(hostname)`

echo "Database Host Name:"
hostname -i
var1=`echo -n $(hostname -i) | base64`

echo "Enter the Directory Name: "
read dir_name

echo "Enter the Initial Tag to use: "
read image_tag

echo "Enter the SSL Private Key File Path: "
read ssl_key
var5=`base64 -w 0 $ssl_key`

echo "Enter the SSL Certificate File Path: "
read ssl_crt
var6=`base64 -w 0 $ssl_crt`

echo "Enter AWS Secret Key: "
read secret_key

echo "Enter AWS Secret Access Key: "
read secret_access_key

echo "$(tput bold)$(tput setaf 4)Exporting Environment variables to OS$(tput sgr 0)"

export DIR_NAME="$dir_name"
export HOSTNAME="$var7"
export POSTGRES_HOST="$var1"
export POSTGRES_DB="$var2"
export POSTGRES_USER="$var3"
export POSTGRES_PASSWORD="$var4"
export SSL_CERT="$var6"
export SSL_KEY="$var5"
export INITIAL_IMAGE_TAG="$image_tag"
export AWS_ACCESS_KEY_ID="$secret_key"
export AWS_SECRET_ACCESS_KEY="$secret_access_key"

## Setting up aws cli to fetch ecr registries

mkdir ~/.aws
touch ~/.aws/config ~/.aws/credentials
cat <<EOF > ~/.aws/credentials
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF

cat <<EOF > ~/.aws/config
[default]
region = us-east-1
EOF

export ECRPASS=$(aws ecr get-login-password --region us-east-1)

## Capturing public IP address

export PublicIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)

## configure kubernetes node environment

echo "$(tput bold)$(tput setaf 4)configuring kuberntes node environment$(tput sgr 0)"

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
source <(kubectl completion bash)
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl taint nodes --all node-role.kubernetes.io/master-

## create project specific namespace

echo "$(tput bold)$(tput setaf 4)creating project specific namespace$(tput sgr 0)"

kubectl create namespace syzygy

## create redis statefulset

echo "$(tput bold)$(tput setaf 4)creating redis statefulset$(tput sgr 0)"

mkdir /home/ubuntu/syzygy-devops/redisdb
cd $DIR_NAME
touch redis-standalone.yaml

cat <<EOF > redis-standalone.yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
    name: redis
    namespace: "syzygy"
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: redis
  local:
    path: /home/ubuntu/syzygy-devops/redisdb
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
            - $HOSTNAME  # hostname of machine. type "hostname" to be updated
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: redis-volume
  namespace: "syzygy"
spec:
  storageClassName: redis
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: "syzygy"
spec:
  type: ClusterIP
  ports:
    - port: 6379
      name: redis
  #clusterIP: None
  selector:
    app: redis
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: "syzygy"
spec:
  selector:
    matchLabels:
      app: redis  # has to match .spec.template.metadata.labels
  serviceName: redis
  replicas: 1
  template:
    metadata:
      labels:
        app: redis  # has to match .spec.selector.matchLabels
    spec:
      containers:
        - name: redis
          image: redis:6.2.5-alpine
          imagePullPolicy: Always
          args: ["--appendonly", "yes", "--save", "900", "1", "--save", "30", "1"]
          ports:
            - containerPort: 6379
              name: redis
          volumeMounts:
            - name: redisdb-data
              mountPath: /home/ubuntu/syzygy-devops/redisdb
      volumes:
      - name: redisdb-data
        persistentVolumeClaim:
          claimName: redis-volume
---
EOF

kubectl apply -f redis-standalone.yaml

## create backend secrets

echo "$(tput bold)$(tput setaf 4)creating backend secrets$(tput sgr 0)"

cd $DIR_NAME
touch secret-creds.yaml

cat <<EOF > secret-creds.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: "backend-secret-creds"
  namespace: "syzygy"
type: kubernetes.io/generic
data:
  POSTGRES_HOST: "$POSTGRES_HOST"
  POSTGRES_DB: "$POSTGRES_DB"
  POSTGRES_USER: "$POSTGRES_USER"
  POSTGRES_PASSWORD: "$POSTGRES_PASSWORD"
  STATIC_ROOT: "L2hvbWUvdWJ1bnR1L3N0YXRpY2ZpbGVz"
  MEDIA_ROOT: "L2hvbWUvdWJ1bnR1L21lZGlh"
---
EOF

kubectl apply -f secret-creds.yaml

## create ssl cert secrets

echo "$(tput bold)$(tput setaf 4)creating ssl cert secrets$(tput sgr 0)"

cd $DIR_NAME
touch ssl.yaml

cat <<EOF > ssl.yaml
---
apiVersion: v1
data:
  tls.crt: $SSL_CERT
  tls.key: $SSL_KEY
kind: Secret
metadata:
  name: syzygy-cert
  namespace: syzygy
type: kubernetes.io/tls
---
EOF

kubectl apply -f ssl.yaml

## configure ECR authentication

echo "$(tput bold)$(tput setaf 4)configure ECR authentication$(tput sgr 0)"

#ECRPASS=$(aws ecr get-login-password --region us-east-1)
kubectl create secret docker-registry aws-ecr-us-east-1 \
    --docker-server=052237514985.dkr.ecr.us-east-1.amazonaws.com \
    --docker-username=AWS \
    --docker-password=$ECRPASS \
    --docker-email=ppatel@codal.com --namespace syzygy

## create static and media files storage class

echo "$(tput bold)$(tput setaf 4)creating static and media files storage class$(tput sgr 0)"

mkdir /home/ubuntu/staticfiles
mkdir /home/ubuntu/media

cd $DIR_NAME
touch staticfilespvc.yaml mediapvc.yaml

cat <<EOF > staticfilespvc.yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
    name: staticfiles
    namespace: syzygy
spec:
  capacity:
    storage: 1Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: staticfiles-sc
  local:
    path: /home/ubuntu/staticfiles
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
            - $HOSTNAME  # change using hostname
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: staticfiles-volume
  namespace: syzygy
spec:
  storageClassName: staticfiles-sc
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Gi
---
EOF

cat <<EOF > mediapvc.yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
    name: media
    namespace: syzygy
spec:
  capacity:
    storage: 3Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: media-sc
  local:
    path: /home/ubuntu/media
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
            - $HOSTNAME  # change using hostname
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: media-volume
  namespace: syzygy
spec:
  storageClassName: media-sc
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 3Gi
---
EOF

kubectl apply -f staticfilespvc.yaml
kubectl apply -f mediapvc.yaml

## create backend deployment

echo "$(tput bold)$(tput setaf 4)creating backend deployment$(tput sgr 0)"

cd $DIR_NAME
touch backend.yaml

cat <<EOF > backend.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: syzygy
  labels:
    app: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: backend
    spec:
      imagePullSecrets:
      - name: aws-ecr-us-east-1
      containers:
      - name: backend
        image: 052237514985.dkr.ecr.us-east-1.amazonaws.com/api:$INITIAL_IMAGE_TAG
        imagePullPolicy: Always
        volumeMounts:
        - name: staticfiles
          mountPath: /home/ubuntu/staticfiles
        - name: media
          mountPath: /home/ubuntu/media
        ports:
          - containerPort: 8000
            name: backend
        #resources:
        #  requests:
        #    cpu: 500m
        #    memory: "512M"
        #  limits:
        #    cpu: 1000m
        #    memory: "1024M"
        readinessProbe:
          tcpSocket:
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 8000
          initialDelaySeconds: 15
          periodSeconds: 20
        env:
          - name: POSTGRES_HOST
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: POSTGRES_HOST
          - name: POSTGRES_DB
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: POSTGRES_DB
          - name: POSTGRES_USER
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: POSTGRES_USER
          - name: POSTGRES_PASSWORD
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: POSTGRES_PASSWORD
          - name: STATIC_ROOT
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: STATIC_ROOT
          - name: MEDIA_ROOT
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: MEDIA_ROOT
        command: ["/code/docker/api.sh"]
      restartPolicy: Always
      volumes:
      - name: staticfiles
        persistentVolumeClaim:
          claimName: staticfiles-volume
      - name: media
        persistentVolumeClaim:
          claimName: media-volume
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: backend
  name: backend
  namespace: syzygy
spec:
  ports:
    - port: 8000
  selector:
    app: backend
---
EOF

kubectl apply -f backend.yaml


## create frontend deployment

echo "$(tput bold)$(tput setaf 4)creating frontend deployment$(tput sgr 0)"

cd $DIR_NAME
touch frontend.yaml

cat <<EOF > frontend.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: syzygy
  labels:
    app: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: frontend
    spec:
      imagePullSecrets:
      - name: aws-ecr-us-east-1
      containers:
      - name: frontend
        image: 052237514985.dkr.ecr.us-east-1.amazonaws.com/frontend:$INITIAL_IMAGE_TAG
        imagePullPolicy: Always
        ports:
          - containerPort: 3000
            name: frontend
        readinessProbe:
          tcpSocket:
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          tcpSocket:
            port: 3000
          initialDelaySeconds: 15
          periodSeconds: 20
        #resources:
        #  requests:
        #    cpu: 500m
        #    memory: "512M"
        #  limits:
        #    cpu: 1000m
        #    memory: "1024M"

---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: syzygy
spec:
  selector:
    app: frontend
  ports:
  - port: 3000
---
EOF

kubectl apply -f frontend.yaml

## create celery deployment

echo "$(tput bold)$(tput setaf 4)creating celery deployment$(tput sgr 0)"

cd $DIR_NAME
touch celery.yaml

cat <<EOF > celery.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celeryapp-syzygy
  namespace: syzygy
  labels:
    app: celeryapp-syzygy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: celeryapp-syzygy
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: celeryapp-syzygy
    spec:
      imagePullSecrets:
      - name: aws-ecr-us-east-1
      containers:
      - name: celeryapp-syzygy
        image: 052237514985.dkr.ecr.us-east-1.amazonaws.com/api:$INITIAL_IMAGE_TAG
        imagePullPolicy: Always
        lifecycle:
          preStop:
            exec:
              command:
              - python
              - /code/drain_celery_worker.py
        volumeMounts:
        - name: staticfiles
          mountPath: /home/ubuntu/syzygy-devops/staticfiles
        - name: media
          mountPath: /home/ubuntu/syzygy-devops/media
        #resources:
        #  requests:
        #    cpu: 500m
        #    memory: "512M"
        #  limits:
        #    cpu: 1000m
        #    memory: "1024M"
        #readinessProbe:
        #  tcpSocket:
        #    port: 8000
        #  initialDelaySeconds: 5
        #  periodSeconds: 10
        #livenessProbe:
        #  tcpSocket:
        #    port: 8000
        #  initialDelaySeconds: 15
        #  periodSeconds: 20
        env:
          - name: POSTGRES_HOST
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: POSTGRES_HOST
          - name: POSTGRES_DB
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: POSTGRES_DB
          - name: POSTGRES_USER
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: POSTGRES_USER
          - name: POSTGRES_PASSWORD
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: POSTGRES_PASSWORD
          - name: STATIC_ROOT
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: STATIC_ROOT
          - name: MEDIA_ROOT
            valueFrom:
              secretKeyRef:
                name: backend-secret-creds
                key: MEDIA_ROOT
          - name: MY_POD_NAME
            valueFrom:
              fieldRef:
                apiVersion: v1
                fieldPath: metadata.name
          - name: C_FORCE_ROOT
            value: "true"
        command: ["/code/docker/celery.sh"]
      restartPolicy: Always
      volumes:
      - name: staticfiles
        persistentVolumeClaim:
          claimName: staticfiles-volume
      - name: media
        persistentVolumeClaim:
          claimName: media-volume
---
EOF

kubectl apply -f celery.yaml

## Set up nginx-ingress

echo "$(tput bold)$(tput setaf 4)creating celery deployment$(tput sgr 0)"

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml
cat > nginx-host-networking.yaml <<EOF
spec:
  template:
    spec:
      hostNetwork: true
EOF

kubectl -n ingress-nginx patch deployment ingress-nginx-controller --patch="$(<nginx-host-networking.yaml)"

kubectl patch svc ingress-nginx-controller -n ingress-nginx --type merge -p '{"spec": {"type": "LoadBalancer", "externalIPs":["'${PublicIP}'"]}}'

## there's one manual step here, need to be automated to be automated

## manual step start ##

# If externalip not automatically assigned after checking with:

# kubectl get svc -n ingress-nginx
## edit following at:
# kubectl edit svc ingress-nginx-controller -n ingress-nginx

#...
#spec:
#  type: LoadBalancer
#  externalIPs:
#  - server-public-ipv4-value[80.10.1.1]

## manual step end ##

## create nginx configmap

echo "$(tput bold)$(tput setaf 4)creating nginx configmap$(tput sgr 0)"

cd $DIR_NAME
touch nginxconfig.yaml

cat <<'EOF' > nginxconfig.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-main
  namespace: syzygy
data:
  nginx.conf: |
    user  nginx;
    worker_processes  1;
    pid        /var/run/nginx.pid;

    events {
        worker_connections  1024;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        log_format json_combined escape=json '{"proxy_protocol_addr": "$proxy_protocol_addr", "remote_addr": "$remote_addr", "proxy_add_x_forwarded_for": "$proxy_add_x_forwarded_for", "time_local": "$time_local", "request" : "$request", "status": "$status", "body_bytes_sent": "$body_bytes_sent", "http_referer":  "$http_referer", "http_user_agent": "$http_user_agent", "request_length" : "$request_length", "request_time": "$request_time", "upstream_addr": "$upstream_addr",  "upstream_response_length": "$upstream_response_length", "upstream_response_time": "$upstream_response_time", "upstream_status": "$upstream_status", "http_host": "$http_host", "host": "$host"}';

        access_log /dev/stdout json_combined;
        error_log /dev/stdout warn;

        sendfile        on;
        #tcp_nopush     on;

        keepalive_timeout  65;

        gzip on;
        gzip_disable "msie6";
        gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript;

        include /etc/nginx/conf.d/*.conf;
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-addon
  namespace: syzygy
data:
  local.conf: |
    upstream upstream_server_backend {
      server backend:8000;
    }

    upstream upstream_server_frontend {
      server frontend:3000;
    }

    server {
      listen 80;
      listen [::]:80 default_server ipv6only=on;
      server_name _;

      keepalive_timeout  65;
      client_max_body_size 100M;

      location / {
        proxy_pass http://upstream_server_frontend;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_read_timeout 1200;
        proxy_connect_timeout 300;
      }

      location /api {
        proxy_pass http://upstream_server_backend;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_read_timeout 1200;
        proxy_connect_timeout 300;
      }

      location /admin {
        proxy_pass http://upstream_server_backend;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_read_timeout 1200;
        proxy_connect_timeout 300;
      }

      location /swagger {
        proxy_pass http://upstream_server_backend;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_read_timeout 1200;
        proxy_connect_timeout 300;
      }

      location /media {
        alias /home/ubuntu/media;
      }

      location /staticapi {
        alias /home/ubuntu/staticfiles;
      }

      location /static {
        proxy_pass http://upstream_server_frontend;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_redirect off;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_read_timeout 1200;
        proxy_connect_timeout 300;
      }

    }
---
EOF

kubectl apply -f nginxconfig.yaml


## create nginx deployment

echo "$(tput bold)$(tput setaf 4)creating nginx deployment$(tput sgr 0)"

cd $DIR_NAME
touch nginxdeployment.yaml

cat <<EOF > nginxdeployment.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginxweb
  name: nginxweb
  namespace: syzygy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginxweb
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: nginxweb
    spec:
      containers:
      - image: nginx:1.19
        name: nginx-container
        ports:
        - containerPort: 80
        resources: {}
        volumeMounts:
        - name: nginx-main
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: nginx-addon
          mountPath: /etc/nginx/conf.d/
        - name: staticfiles
          mountPath: /home/ubuntu/staticfiles
        - name: media
          mountPath: /home/ubuntu/media
        - name: log
          mountPath: /var/log/nginx

      restartPolicy: Always
      volumes:
      - name: nginx-main
        configMap:
          name: nginx-main
      - name: nginx-addon
        configMap:
          name: nginx-addon
      - name: staticfiles
        persistentVolumeClaim:
          claimName: staticfiles-volume
      - name: media
        persistentVolumeClaim:
          claimName: media-volume
      - name: log
        emptyDir: {}

---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginxweb
  name: nginxweb
  namespace: syzygy
spec:
  ports:
  - name: nginxweb
    port: 80
    targetPort: 80
  selector:
    app: nginxweb
---
EOF

kubectl apply -f nginxdeployment.yaml

sleep 100

## create ingress

kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission

echo "$(tput bold)$(tput setaf 4)creating ingress service$(tput sgr 0)"

cd $DIR_NAME
touch ingress.yaml

cat <<EOF > ingress.yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    # certmanager.k8s.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/client-body-buffer-size: 2.5M
    nginx.ingress.kubernetes.io/proxy-body-size: 50M
    nginx.ingress.kubernetes.io/proxy-buffer-size: 50m
    nginx.ingress.kubernetes.io/proxy-max-temp-file-size: 1024m
  name: nginxwebnoauth
  namespace: syzygy
spec:
  rules:
  - host: '*.syzygy.com'
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: nginxweb
            port:
              number: 80
  tls:
  - hosts:
    - '*.syzygy.com'
    secretName: syzygy-cert
---
EOF

kubectl apply -f ingress.yaml

## setup cloudwatch logging using fluentd

echo "$(tput bold)$(tput setaf 4)cloudwatch logging using fluentd$(tput sgr 0)"

cd $DIR_NAME
touch fluetnd-cloudwatch.yaml

cat <<EOF > fluetnd-cloudwatch.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd
  namespace: syzygy

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fluentd
rules:
- apiGroups:
  - ""
  resources:
  - pods
  - namespaces
  verbs:
  - get
  - list
  - watch

---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: fluentd
roleRef:
  kind: ClusterRole
  name: fluentd
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: ServiceAccount
  name: fluentd
  namespace: syzygy
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: syzygy
  labels:
    k8s-app: fluentd-logging
    version: v1
spec:
  selector:
    matchLabels:
      k8s-app: fluentd-logging
      version: v1
  template:
    metadata:
      annotations:
        iam.amazonaws.com/role: us-east-1a.staging.kubernetes.ruist.io-service-role
      labels:
        k8s-app: fluentd-logging
        version: v1
    spec:
      serviceAccount: fluentd
      serviceAccountName: fluentd
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1-debian-cloudwatch
        env:
          - name: LOG_GROUP_NAME
            value: "/syzygy-stage"  # change this value to desired cloudwatch log group 
          - name: AWS_REGION
            value: "us-east-1"
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 100m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        # When actual pod logs in /var/lib/docker/containers, the following lines should be used.
        - name: dockercontainerlogdirectory
          mountPath: /var/lib/docker/containers
          readOnly: true
        # When actual pod logs in /var/log/pods, the following lines should be used.
        #- name: dockercontainerlogdirectory
        #  mountPath: /var/log/pods
        #  readOnly: true
      terminationGracePeriodSeconds: 30
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      # When actual pod logs in /var/lib/docker/containers, the following lines should be used.
      - name: dockercontainerlogdirectory
        hostPath:
          path: /var/lib/docker/containers
      # When actual pod logs in /var/log/pods, the following lines should be used.
      #- name: dockercontainerlogdirectory
      #  hostPath:
      #    path: /var/log/pods
---
EOF

kubectl apply -f fluetnd-cloudwatch.yaml    
