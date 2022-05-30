# Lets Encrypt Scripts

Public Git URL: https://git.sosdg.org/brielle/lets-encrypt-scripts

By: Brielle Bruns <bruns@2mbit.com>

These are various scripts to make LetsEncrypt easier to use.

# Files
## Main Scripts

gen-cert.sh  - Main script to make it easy to generate LE certs for domain(s)

gen-unifi-cert.sh - Script to add LE cert to a Unifi controller

## Support Files

DSTROOTCAX3.txt - Root CA cert for use with the gen-unifi-cert.sh script (now optional and unneeded as the cert is embedded)

apache-le-alias.conf - Use with apache for LE well-known alias config

apache-le-proxy.conf - Use with apache for LE well-known proxy config

# How To Use

## gen-cert.sh

1. Do initial cert generation (if using webroot, see script contents for more methods of authentication):
	
		gen-cert.sh -e email@address.com -d somedomain.com -d otherdomain.com -r /var/www/letsencrypt-root/
		
2. Copy cron/renew-ssl-weekly.sh to /etc/cron.weekly, edit as appropriate

3. Run:

		chmod 750 /etc/cron.weekly/renew-ssl-weekly.sh  
		
3. Script will now run weekly and renew the certificate if necessary ( < 30 days remain).  Don't forget to add any necessary file copies/symlinks/service restarts as needed once the scripts are updated.

## gen-unifi-cert.sh

1. Do initial cert generation:
	
		gen-unifi-cert.sh -e email@address.com -d unifi.somedomain.com -d unifi.someotherdomain.com
		
2. Put in /etc/cron.weekly/renew-unifi-ssl if everything works okay:
	
		/path/to/script/gen-unifi-cert.sh -r -d unifi.somedomain.com -d unifi.someotherdomain.com
		
3. Script will now run weekly and renew the certificate if necessary ( < 30 days remain) and restart unifi only if cert has been renewed.