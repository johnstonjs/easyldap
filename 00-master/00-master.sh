#!/bin/sh
# A shell script to automate importing of LDIFs within this folder
# TODO: Check for dependencies (ldapmodify, ldapadd, etc)

sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f /etc/ldap/schema/ppolicy.ldif
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ldif/01-logging.ldif
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ldif/02-letsencrypt.ldif
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ldif/03-configtls.ldif
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ldif/04-bind_anon.ldif
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ldif/05-set_require.ldif
sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f ldif/06-memberof_config.ldif
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ldif/07-refint1.ldif
sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f ldif/08-refint2.ldif
sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f ldif/09-ppolicy.ldif
sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f ldif/10-openssh-lpk.ldif
sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f ldif/11-sudo.ldif
sudo ldapadd -Q -Y EXTERNAL -H ldapi:/// -f ldif/12-postfix.ldif
sudo ldapadd -x -D cn=admin,dc=example,dc=com -H ldaps://localhost:636 -W -f ldif/20-users_and_groups.ldif
sudo ldapmodify -x -D cn=admin,dc=example,dc=com -H ldaps://localhost:636 -W -f ldif/21-import_ssh_pubkey.ldif
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ldif/22-system_access.ldif
sudo ldapadd -x -D cn=admin,dc=example,dc=com -H ldaps://localhost:636 -W -f ldif/23-sudo_rules.ldif
sudo ldapadd -x -D cn=admin,dc=example,dc=com -H ldaps://localhost:636 -W -f ldif/24-clients.ldif
sudo ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f ldif/40-index.ldif
