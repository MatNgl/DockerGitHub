#!/bin/bash

# Définir les variables
GITLAB_CONTAINER_NAME="gitlab"
GITLAB_RUNNER_CONTAINER_NAME="gitlab-runner"
GITLAB_REGISTRATION_TOKEN="glrt-7JZzCykAxyZCLMHADrhS"
GITLAB_URL="http://gitlab"
GITLAB_ROOT_PASSWORD="dockerfile"

# Configurer Git pour éviter les conversions LF/CRLF
git config --global core.autocrlf false
git config --global core.eol lf

# Créer le fichier .gitignore
cat > .gitignore <<EOF
# Ignorer les fichiers de configuration sensibles
config/gitlab-secrets.json
config/gitlab.rb
config/initial_root_password
config/ssh_host_ecdsa_key
config/ssh_host_ecdsa_key.pub
config/ssh_host_ed25519_key
config/ssh_host_ed25519_key.pub
config/ssh_host_rsa_key
config/ssh_host_rsa_key.pub

# Ignorer les fichiers de données et de socket
data/*.socket
data/**/*.socket
data/gitlab-rails/upgrade-status/*
data/gitlab-shell/config.yml
data/gitlab-workhorse/VERSION
data/gitlab-workhorse/config.toml
data/gitlab-workhorse/sockets/*
data/.gitconfig
data/alertmanager/alertmanager.yml
data/git-data/repositories/.gitaly-metadata
data/gitaly/VERSION
data/gitaly/config.toml
data/gitaly/gitaly.socket
data/gitaly/run/*
data/gitlab-rails/sockets/*
data/gitlab-rails/etc/*
data/gitlab-rails/RUBY_VERSION
data/gitlab-rails/REVISION
data/gitlab-exporter/RUBY_VERSION
data/gitlab-exporter/gitlab-exporter.yml
data/gitlab-kas/VERSION
data/gitlab-kas/gitlab-kas-config.yml

# Ignorer les logs Nginx
data/nginx/logs/

# Ignorer les fichiers générés par logrotate
data/logrotate/logrotate.status

# Ignorer les fichiers de configuration sensibles et les logs
.gitlab/config/secrets.yml
.gitlab/logs/
.gitlab/data/

# Ignorer les configurations du runner
runner/config/

# Ignorer les fichiers de logs
logs/*

# Ignorer le fichier de configuration CI/CD de GitLab
.gitlab-ci.yml
EOF

# Créer le fichier docker-compose.yml combiné pour GitLab et GitLab Runner
cat > docker-compose.yml <<EOF
version: '3'
services:
  gitlab:
    image: 'gitlab/gitlab-ee:latest'
    restart: always
    hostname: 'localhost'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url '${GITLAB_URL}'
        gitlab_rails['lfs_enabled'] = true
    ports:
      - '80:80'
      - '443:443'
      - '22:22'
    volumes:
      - './gitlab/config:/etc/gitlab'
      - './gitlab/logs:/var/log/gitlab'
      - './gitlab/data:/var/opt/gitlab'

  gitlab-runner:
    image: gitlab/gitlab-runner:latest
    restart: always
    volumes:
      - './runner/config:/etc/gitlab-runner'
      - '/var/run/docker.sock:/var/run/docker.sock'
    environment:
      - DOCKER_TLS_CERTDIR=/certs
      - DOCKER_DRIVER=overlay2
    entrypoint: >
      /bin/bash -c "
      if [ ! -f /etc/gitlab-runner/config.toml ]; then
        while ! curl -s ${GITLAB_URL} > /dev/null; do
          echo 'Waiting for GitLab to be available...'
          sleep 5
        done
        gitlab-runner register --non-interactive --executor docker --docker-image alpine:latest --url ${GITLAB_URL} --registration-token ${GITLAB_REGISTRATION_TOKEN} --description 'docker-runner' --tag-list 'docker,aws' --run-untagged --locked=false --access-level not_protected
      fi
      gitlab-runner run --user=gitlab-runner --working-directory=/home/gitlab-runner"
EOF

# Démarrer GitLab et GitLab Runner
docker-compose up -d

# Attendre que GitLab soit entièrement démarré
echo "Waiting for GitLab to be fully started..."
sleep 180

# Réinitialiser le mot de passe root
docker exec -it ${GITLAB_CONTAINER_NAME} gitlab-rails runner "user = User.where(id: 1).first; user.password = '${GITLAB_ROOT_PASSWORD}'; user.password_confirmation = '${GITLAB_ROOT_PASSWORD}'; user.save!"

# Nettoyer l'index de Git et ajouter les fichiers
git rm -r --cached .
git add .
git commit -m "Clean up the repository and re-add files"
git push origin main

# Créer un fichier .gitlab-ci.yml pour les pipelines CI/CD
cat > .gitlab-ci.yml <<EOF
stages:
  - build
  - test

build-job:
  stage: build
  script:
    - echo "Building the project..."
    - echo "Build complete!"

test-job:
  stage: test
  script:
    - echo "Running tests..."
    - echo "Tests complete!"
EOF

# Ajouter et pousser le fichier .gitlab-ci.yml vers GitLab
git add .gitlab-ci.yml
git commit -m "Add CI/CD pipeline configuration"
git push origin main

echo "Setup completed!"
