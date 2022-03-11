# EasyLDAP: Easy Configuration of OpenLDAP for Linux User Authentication

This guide contains scripts and configuration files to **easily**:
1.  Install the [OpenLDAP](https://openldap.org) Server
2.  Encrypt LDAP traffic using [LetsEncrypt](https://letsencrypt.org) Certs
3.  Store SSH keys for each User on the LDAP Server
4.  Manage SUDO rules for each Client System on the LDAP Server
5.  Cache User information on Client Systems to mitigate LDAP Server downtime
6.  Create User Home Directories on first login to each Client System

This configuration is intended for a small number of Users (< 100) with a
similar number of Groups.  It should be extensible beyond that, but has not
been tested.

All of these capabilities will be accomplished with relatively small memory and
filesystem usage to run on a low-cost hosted virtual machine shared with other
services.

Management of the LDAP Server can be performed using web-based tools such as
[LDAP Account Manager](https://www.ldap-account-manager.org) or terminal-based
tools such as [LDAPScripts](https://packages.ubuntu.com/bionic/ldapscripts).

## Background

Managing user accounts, SSH keys, and SUDO permissions across multiple Linux
systems is difficult and can be insecure.  There are a variety of tools and
services available to address this problem, each with benefits and drawbacks.

1.  [FreeIPA](https://freeipa.org): The gold standard in user and system
management.  While it is robust and highly extensible, it has steep memory
and storage requirements.  It also is challenging to configure on some hosting
providers, such as [AWS](https://aws.amazon.com), due to public/private IP
addresses.

2.  [OpenLDAP](https://openldap.org): An open source implementation of the
Lightweight Directory Access Protocol (LDAP), OpenLDAP is robust and flexible
but is widely seen as difficult to use.  Its memory and storage requirements
are well within the capacity of modern compute equipment and services.

3.  [JumpCloud](https://jumpcloud.com): A Directory-as-a-Service provider,
JumpCloud is free for up to ten (10) User accounts.  While it supports LDAP,
it relies on *agent* software to be installed for SUDO rules.  The *agent* is
very flexible and easy to install, but does not support ARM-based systems such
as Raspberry Pi.

4.  [FoxPass](https://foxpass.com): A Directory-as-a-Service provider, FoxPass
is free for a small number of User accounts.  It supports LDAP, and has scripts
that make installation incredibly simple and works on many architectures.
Support for SUDO rules costs extra.

My goal was to have a central Directory for User information that supports **SSH
key management**, **SUDO rules**, and can withstand days of **Server downtime**
without losing access to the Client Systems.  It should work over the internet
or within a private network, and require **no custom certificates** between
the Server and Client for encrypted connections.

With much patience and perseverance, [OpenLDAP](https://openldap.org) can
provide all of these capabilities using only packages available in modern
Linux distributions.  All of the scripts and configurations in this guide have
been tested against [Ubuntu](https://ubuntu.org) 18.04, 19.04, and 20.04,
as well as [Debian](https://debian.org) 10.

## Systems and Software

For the purposes of this guide, the LDAP Server can be any **Linux system**
with a **fully qualified domain name** and **accessible on port 636**.
Scripts provided have only been tested on [Ubuntu](https://ubuntu.org) 18.04, 19.04, and 20.04 as well as [Debian](https://debian.org) 10.

The configuration of OpenLDAP described here has been successfully tested
on an [AWS](https://aws.amazon.com) EC2 instance with a static IP address, as
well as bare metal behind a home firewall with a changing IP address, dynamic
DNS service, and port forwarding.

### OpenLDAP

[OpenLDAP](https://openldap.org) is available in the standard package
repositories of every major Linux distribution.  On Ubuntu, the package name
is [slapd](https://packages.ubuntu.com/bionic/slapd).  It should be installed
with the package [ldap-utils](https://packages.ubuntu.com/bionic/ldap-utils)
which is required for the scripts in this guide and very useful for managing
the settings and content of the OpenLDAP Server.

Older documentation for [OpenLDAP](https://openldap.org) (prior to ~2015) will
refer to changing settings via configuration files in `/etc/ldap`.  These files
are deprecated in recent versions of OpenLDAP, and almost all settings for
OpenLDAP are contained within the database itself.  This guide will demonstrate
the use of ldap-utils such as `ldapadd` and `ldapmodify` to configure and manage
the OpenLDAP server.

OpenLDAP supports [replication](https://help.ubuntu.com/lts/serverguide/openldap-server.html#openldap-server-replication)
to other Servers for high availability, however that functionality is not used
in this guide.  Rather than hosting multiple LDAP Servers, we will cache
credentials on Client Systems to maintain User access even if the LDAP Server
is down for extended periods.

### SSSD

System Security Services Daemon, or [SSSD](https://pagure.io/SSSD/sssd/), is a
set of daemons to manage access to systems through authentication mechanisms
such as LDAP, Kerberos, and FreeIPA.  If you decided to use FreeIPA instead of
OpenLDAP to manage User accounts and access controls, you would still use SSSD
on client systems.

On Ubuntu (and Debian), SSSD is provided by the metapackage
[sssd](https://packages.ubuntu.com/bionic/sssd) and should be installed on
clients along with related packages
[libpam-sss](https://packages.ubuntu.com/bionic/libpam-sss),
[libnss-sss](https://packages.ubuntu.com/bionic/libnss-sss),
and [libsss-sudo](https://packages.ubuntu.com/bionic/libsss-sudo).  These
packages provide modules and libraries for
[PAM authentication](https://en.wikipedia.org/wiki/Linux_PAM), name resolution
by [NSS](https://en.wikipedia.org/wiki/Name_Service_Switch), and
[SUDO](https://en.wikipedia.org/wiki/Sudo) to support User login, permissions,
and SUDO rules from the LDAP Server via SSSD.  Home Directories for each User
will even be created on their first login to each Client System.

As previously noted, we will avoid the need to set up a second LDAP Server as
a replica of the first to maintain high availability.  SSSD natively supports
[caching](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/deployment_guide/sssd-cache-cred)
credentials for when the LDAP Server is unavailable.

### Certbot

Most guides to configuring OpenLDAP rely upon self-signed certificates for
network traffic encryption.  [Let'sEncrypt](https://letsencrypt.org) provides
free certificates signed by a trusted Certificate Authority.  With the
[certbot](https://packages.ubuntu.com/bionic/certbot) package installed,
OpenLDAP can be configured to use signed encryption certificates from
Let'sEncrypt for SSL connections.

This guide will show how to configure OpenLDAP to use certificates from
Let'sEncrypt, however configuration of certbot to acquire those certificates is
left to the reader.  Instructions are
[available](https://certbot.eff.org/lets-encrypt/ubuntubionic-apache.html)
[for](https://certbot.eff.org/lets-encrypt/ubuntubionic-nginx)
[a](https://certbot.eff.org/lets-encrypt/debianbuster-nginx)
[variety](https://certbot-dns-route53.readthedocs.io/en/stable/)
[of](https://www.digitalocean.com/community/tutorials/how-to-use-certbot-standalone-mode-to-retrieve-let-s-encrypt-ssl-certificates-on-ubuntu-1804)
[methods](https://medium.com/@jeremygale/how-to-set-up-a-free-dynamic-hostname-with-ssl-cert-using-google-domains-58929fdfbb7a).

Please note that the Let'sEncrypt certificates must be installed on the
OpenLDAP server in `/etc/letsencrypt/live`, and so readers should be careful
if using a Docker container to run
[certbot](https://hub.docker.com/r/certbot/certbot/).

### OpenSSH

It is likely that you already have [OpenSSH](https://www.openssh.com) installed
for remote terminal and file system access to each Linux system.  Ideally, you
also use
[public key authentication](https://www.debian.org/devel/passwordlessssh), as it
is far more secure than passwords.

Versions of OpenSSH distributed with recent Linux distributions, such as the
[openssh-server](https://packages.ubuntu.com/bionic/openssh-server) package for
Ubuntu, have configuration options to retrieve public keys from an LDAP Server
via SSSD.  In this guide, we will show how to properly configure OpenSSH to
allow password-less authentication via keys stored in your LDAP Server.

## Server Installation

This guide assumes the reader is decently familiar with Linux system
administration.  Certain steps, such as package installation and management,
are particular to Ubuntu (or Debian) distributions.  Readers using other
distributions should be able to adapt them easily.  Installation requires root
(or SUDO) access to the desired Linux system.  The LDAP Server must
be accessible to any Clients on port 636.

For the purposes of this guide, the base Domain Name will be *example.com*.  The
LDAP Server itself will use the hostname *ldap.example.com*.

### OpenLDAP

Ensure hostname is set appropriately:
```
sudo hostnamectl set-hostname ldap.example.com
```

Install OpenLDAP and the LDAP Utilities:
```
sudo apt install slapd ldap-utils
```

The installation routine will prompt you for an Administrator password.  It can
be left blank at this time, as we will immediately reconfigure the *slapd*
installation.
```
sudo dpkg-reconfigure slapd
```
For each screen of the reconfiguration script, enter the following:
1.  Omit OpenLDAP Server Configuration: **NO**
2.  DNS Domain Name: **example.com**
3.  Organization Name: **example.com**
4.  Administrator Password: **YOUR_ADMIN_PASSWORD**
5.  Confirm Password: **YOUR_ADMIN_PASSWORD_AGAIN**
6.  Database Backend to Use: **MDB**
7.  Do you want the database to be removed with slapd is purged: **NO**
8.  Move old database?  **YES**

**Note:** Configuration of the LDAP Server can be restarted at any time by
repeating the `dpkg-reconfigure slapd` process as shown here.  This can be
useful if a mistake is made during the configuration process.

Edit `/etc/defaults/slapd` to configure *slapd* for SSL/TLS connections.  Look
for the line:
```
SLAPD_SERVICES="ldap:/// ldapi:///"
```
and edit it to include `ldaps:///`.
```
SLAPD_SERVICES="ldap:/// ldapi:/// ldaps:///"
```
Note: You can also remove the `ldap:///` portion of this configuration if you
want to disable non-encrypted LDAP traffic entirely.

Restart *slapd*
```
sudo systemctl restart slapd
```

### Let'sEncrypt

As noted previously, this guide assumes that the reader has configured Certbot
for their particular IP address and DNS provider.  Your LDAP Server should
have a folder named *ldap.example.com* in */etc/letsencrypt/live*.
```
root@ldap:~# sudo ls -l /etc/letsencrypt/live/
total 4
drwxr-xr-x 2 root root 4096 Oct 13 14:55 ldap.example.com
```

On Ubuntu (and Debian) systems, the *slapd* process is run by the System User
*openldap*.  Because of the permissions on the folder */etc/letsencrypt/live*,
the System User *openldap* is unable to read the Let'sEncrypt certificates
without additional access control settings.  Fortunately, modern Linux
distributions also include enhanced access control utilities.

Ensure that the package [acl](https://packages.ubuntu.com/bionic/acl) is
installed:
```
sudo apt install acl
```
Now set the access controls for the certificate files we will use for OpenLDAP.
```
sudo setfacl -m u:openldap:rx /etc/letsencrypt/live
sudo setfacl -m u:openldap:rx /etc/letsencrypt/archive
sudo setfacl -m u:openldap:r /etc/letsencrypt/live/ldap.example.com/fullchain.pem
sudo setfacl -m u:openldap:r /etc/letsencrypt/live/ldap.example.com/cert.pem
sudo setfacl -m u:openldap:r /etc/letsencrypt/live/ldap.example.com/privkey.pem
```

Since Let'sEncrypt certificates are renewed regularly by Certbot, these
permissions need to be reset following certificate renewal.  That can be done
by creating a renewal post-hook in `/etc/letsencrypt/renewal-hooks/post`:
```
#!/bin/sh
#
# /etc/letsencrypt/renewal-hooks/post/reload_services_letsencrypt.sh
#
# Reload services that use LetsEncrypt certificates if the certificate is
# renewed by certbot.  Only restarts the services if renewal is both
# required and successful.
#
# To add additional services, enter additional lies with the form:
#                systemctl reload *service_name*
#                               or
#                systemctl restart *service_name*
# where *service_name* is the name of a service like nginx or dovecot

# Restore permissions for LDAP server (slapd) to keys and restart
setfacl -m u:openldap:rx /etc/letsencrypt/live
setfacl -m u:openldap:rx /etc/letsencrypt/archive
setfacl -m u:openldap:r /etc/letsencrypt/live/ldap.example.com/fullchain.pem
setfacl -m u:openldap:r /etc/letsencrypt/live/ldap.example.com/cert.pem
setfacl -m u:openldap:r /etc/letsencrypt/live/ldap.example.com/privkey.pem
systemctl restart slapd
```

Ensure that the post-hook script is executable ('chmod a+x').

Additionally, if your Linux distribution uses [AppArmor](https://en.wikipedia.org/wiki/AppArmor),
you need to edit `/etc/apparmor.d/local/usr.sbin.slapd` to contain:
```
/etc/letsencrypt/live/ldap.example.com r,
/etc/letsencrypt/archive/ldap.example.com r,
/etc/letsencrypt/archive/ldap.example.com/** r,
```

With all of these configurations in place, the Let'sEncrypt certificates should
be accessible to *slapd* on modern Linux distributions.  These have been tested
on Ubuntu 18.04, 19.04, 20.04, and Debian 10.

During a later step we will configure *slapd* to load these certificates for
encryption.  If you receive error code 80 at that time, it means that the
certificates are not accessible by *slapd*.

## Server Configuration

Configuration of *slapd* on modern Linux distributions is performed by changing
settings within the database itself.  There is a section of the database,
`cn=config`, which exists for *slapd* configuration parameters.  Modifications
to the database are made by using the *ldapadd* or *ldapmodify* commands, and
can draw information from *LDIF* files to simplify.

This guide includes a set of *LDIF* files which, when modified appropriately,
will completely configure *slapd* to support the stated objectives above.

It is **highly** recommended that the reader creates a **private** repository
of the *LDIF* files that are appropriately modified for their needs.  This
includes editing hostnames, User names, details, passwords, and keys, as well
as Client system names and passwords.  This will allow for version control
of the modified configuration files tailored to their LDAP Server.

All of the *LDIF* files needed are contained in [00-master/ldif](00-master/ldif)
and contain comments to explain their function and implementation:
1.  [01-logging](00-master/ldif/01-logging.ldif): Sets the logging level for
OpenLDAP to be fairly verbose, allowing for troubleshooting during configuration.
2.  [02-letsencrypt](00-master/ldif/02-letsencrypt.ldif): Configures *slapd* to
use the LetsEncrypt certificates specified above for encrypted traffic with
Client systems.  **This file must be modified in three places to point to the
correct location on the LDAP Server.**  (Replace `ldap.example.com` with the
appropriate FQDN).
3.  [03-configtls](00-master/ldif/03-configtls.ldif): Sets the encryption
protocols to be used for traffic with Client systems.
4.  [04-bind_anon](00-master/ldif/04-bind_anon.ldif): Disallows anonymous bind
to the LDAP Server (Clients must have an established password).
5.  [05-set_require](00-master/ldif/05-set_require.ldif): Sets required
conditions for authentication to the LDAP Server.
6.  [06-memberof_config.ldif](00-master/ldif/06-memberof_config.ldif): Loads
the memberOf module to easily check if a user is member of a given group.  This
is useful for restricting access to various Client systems.
7.  [07-refint1.ldif](00-master/ldif/07-refint1.ldif):  Loads a module to
enable the memberOf functionality.
8.  [08-refint2.ldif](00-master/ldif/08-refint2.ldif): Loads another module
required for memberOf functionality.
9.  [09-ppolicy.ldif](00-master/ldif/09-ppolicy.ldif): Loads another module
required for password policy functionality (avoids syslog errors).
10.  [10-openssh-lpk.ldif](00-master/ldif/10-openssh-lpk.ldif): Loads the
OpenSSH Public Key schema so that keys can be added for Users.
12.  [11-sudo.ldif](00-master/ldif/11-sudo.ldif): Loads the SUDO schema so that
SUDO rules can be managed on the LDAP Server for each User.
12.  [12-postfix.ldif](00-master/ldif/12-postfix.ldif): Loads the schema for
mail routing so that Users can send/receive email.
13.  [20-users_and_groups.ldif](00-master/ldif/20-users_and_groups.ldif):
Populates users and groups for the LDAP Server.  **This file must be modified
in MANY places to have the User and Group settings desired by the reader.**  The
appropriate modifications should be intuitive from the comments but include
setting the appropriate LDAP domain (*dc=example,dc=com*), User name (*user1*),
and many other settings.
14.  [21-import_ssh_pubkey.ldif](00-master/ldif/21-import_ssh_pubkey.ldif):
Adds SSH Public Keys to the specified User.  **This file must be modified in
MANY places to add the reader's SSH Public Keys**.  The appropriate modifications
should be intuitive from the comments.
15.  [22-system_access.ldif](00-master/ldif/22-system_access.ldif): Sets LDAP
access permissions so that Client systems can allow User authentication.  **This
file must be modified in two places to point to the appropriate LDAP domain.**
Replace the *dc=example,dc=com* as appropriate.
16.  [23-sudo_rules.ldif](00-master/ldif/23-sudo_rules.ldif): Sets the SUDO
rules for Client systems.  **This file must be modified in three places to point
to the appropraite LDAP domain.**  Replace the *dc=example,dc=com* as
appropriate.
17.  [24-clients.ldif](00-master/ldif/24-clients.ldif): Creates a unique
password for every Client system (so that they can be disabled individually if
needed).  **This file must be modified in multiple places.**  The appropriate
modiifcations should be intuitive from the examples and comments.
Replace the *dc=example,dc=com* as appropriate.
18.  [40-index.ldif](00-master/ldif/40-index.ldif):  Attempts to correct
various system logging errors that complain about missing database indices.
These errors seem to have no impact on system performance, but are easily
corrected.
18.  [50-lower_logging](00-master/ldif/50-lower_logging.ldif): Reduces the
quantity of logs generated once properly configured.

A [script](00-master/00-master.sh) is provided to automate the incorporation of these database
configuration files.  **It must be modified in multiple places to point to the
appropraite LDAP domain.**

If all of these scripts are maintained in a **private** repository and
configured appropriately, the reader can configure the LDAP Server quickly
by executing `./00-master.sh` from the `00-master` folder of the repository.

Further, all Users, Groups, and Clients can be maintained in this **private**
repository allowing for rapid reconstitution of the LDAP Server in the event of
system failure.

### LDAP Server Logging

Log events generated by *slapd* can be sent to a dedicated log file if desired.
An *rsyslog* configuration file is [provided](rsyslog/10-slapd.conf) with
comments explaining how to implement.

Previous versions of this LDAP configuration resulted in repeated log events
regarding lack of database indices.  The file
[40-index.ldif](00-master/ldif/40-index.ldif) has been updated
extensively to avoid these.  Configuration can be easily seen be executing the
command:
```
sudo cat /etc/ldap/slapd.d/cn=config/olcDatabase={1}mdb.ldif
```

This file should not be modified directly.  Further updates to indexing should
be made through [40-index.ldif](00-master/ldif/40-index.ldif).

### LDAP Server Protection

If the reader users *fail2ban* to protect against attempted intrusions, it
can be configred to protect the Open LDAP server.  Simply add the following
lines to `/etc/fail2ban/filter.local`.

```
[slapd]
enabled  = true
port     = ldap.ldaps
logpath  = /var/log/slapd.log
```

## Client Installation

Using LDAP for login authentication requires the installation of some software
that integrates LDAP with
[Linux-PAM (Pluggable Authentication Modules for Linux)](http://www.linux-pam.org).
There are two primary choices for this, [pam-ldap](https://wiki.debian.org/LDAP/PAM)
and [SSSD](https://en.wikipedia.org/wiki/System_Security_Services_Daemon)].
This guide will focus on *SSSD* as it better integrates remote and local groups
as well as SSH keys.

On every Client system, install the _sssd_ package and dependencies.

```
sudo apt -y install sssd libpam-sss libnss-sss libsss-sudo sssd-tools
```

## Client Configuration

Configuration of your Client Systems to authenticate against the LDAP Server
involves the following steps:

1.  Enable automatic creation of Home Directories upon a User's first login
2.  Configure OpenSSH to check against Public Keys stored on the LDAP Server
3.  Appropriately configure *SSSD* to connect to your LDAP Server

### Home Directories

On Ubuntu (and Debian) based systems, automatic creation of User Home
Directories can be easily enabled by the command:

```
sudo pam-auth-update --enable mkhomedir
```

For other Linux distributions, methods may vary.  Documentation on the PAM
*mkhomedir* module is
[available here](http://www.linux-pam.org/Linux-PAM-html/sag-pam_mkhomedir.html).

### Configure OpenSSH

This guide assumes that the reader already has OpenSSH configured appropriately
(such as disabling password authentication).

Edit the file `/etc/ssh/sshd_config` and include the following settings:
```
AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys
AuthorizedKeysCommandUser root
```
Most Linux distributions ship with a default *sshd_config* file that has these
settings commented out.

Now restart the OpenSSH server:
```
sudo systemctl restart sshd
```

### Configure SSSD

Before doing this step, ensure that you have root access to the Client System
with a User account that is not shared with accounts you've configured on the
LDAP Server to avoid being locked out by a mis-configuration.

Edit the file `/etc/sssd/sssd.conf` (it may not yet exist), and enter the
following contents (assuming you've configured the LDAP Server as shown in this
guide).

```
# /etc/sssd/sssd.conf
# SSSD settings for EXAMPLE.COM

[sssd]
config_file_version = 2
reconnection_retries = 3
# The services line is not needed in Ubuntu 20.04 and causes errors
# Uncomment it for earlier versions
# services = nss, pam, ssh, sudo
domains = example

[nss]
filter_groups = root
filter_users = root ldap.bind

[pam]
offline_credentials_expiration = 30

[sudo]

[ssh]

[domain/example]
debug_level = 0
enumerate = true
id_provider = ldap
auth_provider = ldap
cache_credentials = true
ldap_uri = ldaps://ldap.example.com:636
ldap_search_base = ou=People,dc=example,dc=com
ldap_default_bind_dn = cn=clientsystem,ou=Clients,dc=example,dc=com
ldap_default_authtok = client_system_password
ldap_group_search_base = ou=Groups,dc=example,dc=com
ldap_group_member = memberUid
ldap_user_ssh_public_key = sshPublicKey
ldap_tls_reqcert = demand
sudo_provider = ldap
ldap_sudo_search_base = ou=SUDO,dc=example,dc=com
access_provider = ldap
ldap_access_filter = memberOf=cn=linux,ou=Lists,dc=example,dc=com
```

Set permissions appropriately for `/etc/sssd/sssd.conf`
```
sudo chmod 600 /etc/sssd/sssd.conf
```

Now restart *SSSD*
```
sudo systemctl restart sssd
```

If appropriately configured, Users configured on the LDAP Server should
show with execution of the command `getent passwd`
```
~$ getent passwd
*LOCAL USER INFORMATION*
user1:*:10000:10000:User One:/home/user1:/bin/bash
```
