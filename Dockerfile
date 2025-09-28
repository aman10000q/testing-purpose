FROM postgres:14

# Copy your Bash script to the container
COPY . .
RUN apt update
RUN apt install git -y
RUN apt install curl -y
RUN curl -L https://github.com/golang-migrate/migrate/releases/download/v4.14.1/migrate.linux-amd64.tar.gz | tar xvz
RUN mv migrate.linux-amd64 $GOPATH/bin/migrate
# Set execute permissions on the script
RUN chmod +x cleanup.sh

# Specify the default command to run when the container starts
CMD ["/bin/bash", "-c", "bash cleanup.sh"]
