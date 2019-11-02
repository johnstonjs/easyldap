#!/bin/sh
# A shell script to configure system as LDAP Client for authentication
#
sudo apt -y install sssd libpam-sss libnss-sss libsss-sudo
sudo cp sssd.conf /etc/sssd/
sudo systemctl restart sssd
sudo systemctl restart sshd
sudo pam-auth-update --enable mkhomedir
