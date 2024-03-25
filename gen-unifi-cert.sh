#!/usr/bin/env bash
# Modified script from here: https://github.com/FarsetLabs/letsencrypt-helper-scripts/blob/master/letsencrypt-unifi.sh
# Modified by: Brielle Bruns <bruns@2mbit.com>
# Download URL: https://source.sosdg.org/brielle/lets-encrypt-scripts
# Version: 1.99.10
# Last Changed: 03/24/2024
# 02/02/2016: Fixed some errors with key export/import, removed lame docker requirements
# 02/27/2016: More verbose progress report
# 03/08/2016: Add renew option, reformat code, command line options
# 03/24/2016: More sanity checking, embedding cert
# 10/23/2017: Apparently don't need the ace.jar parts, so disable them
# 02/04/2018: LE disabled tls-sni-01, so switch to just tls-sni, as certbot 0.22 and later automatically fall back to http/80 for auth
# 05/29/2018: Integrate patch from Donald Webster <fryfrog[at]gmail.com> to cleanup and improve tests
# 09/26/2018: Change from TLS to HTTP authenticator
# 09/22/2021: Update root certs
# 10/10/2021: Split out import process for root certs, and fix quirkiness with cert chains
# 10/11/2021: Minor fixes, add keystore cli opt, variable references
# 03/24/2024: Adds legacy option for OpenSSL 3.x to fix issue with keystore format

# Location of LetsEncrypt binary we use.  Leave unset if you want to let it find automatically
#LEBINARY="/usr/src/letsencrypt/certbot-auto"

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

KEYSTORE="/usr/lib/unifi/data/keystore"


function usage() {
  echo "Usage: $0 -d <domain> [-e <email>] [-r] [-i] [-k <keystore>] [-l]"
  echo "  -d <domain>: The domain name to use."
  echo "  -e <email>: Email address to use for certificate."
  echo "  -r: Renew domain."
  echo "  -i: Insert only, use to force insertion of certificate."
  echo "  -k: Specify keystore to use."
  echo "  -h: This usage description."
  echo "  -l: Use OpenSSL 3.x legacy option."
}

while getopts "hirld:e:k:" opt; do
  case $opt in
    i) onlyinsert="yes";;
    r) renew="yes";;
    d) domains+=("$OPTARG");;
    e) email="$OPTARG";;
    k) userkeystore="$OPTARG";;
    l) uselegacy="yes";;
    h) usage
       exit;;
  esac
done

DEFAULTLEBINARY="/usr/bin/certbot /usr/bin/letsencrypt /usr/sbin/certbot
  /usr/sbin/letsencrypt /usr/local/bin/certbot /usr/local/sbin/certbot
  /usr/local/bin/letsencrypt /usr/local/sbin/letsencrypt
  /usr/src/letsencrypt/certbot-auto /usr/src/letsencrypt/letsencrypt-auto
  /usr/src/certbot/certbot-auto /usr/src/certbot/letsencrypt-auto
  /usr/src/certbot-master/certbot-auto /usr/src/certbot-master/letsencrypt-auto"

if [[ ! -v LEBINARY ]]; then
  for i in ${DEFAULTLEBINARY}; do
    if [[ -x ${i} ]]; then
      LEBINARY=${i}
      echo "Found LetsEncrypt/Certbot binary at ${LEBINARY}"
      break
    fi
  done
fi

# Command line options depending on New or Renew.
NEWCERT="--renew-by-default certonly"
RENEWCERT="-n renew"

# Check for required binaries
if [[ ! -x ${LEBINARY} ]]; then
  echo "Error: LetsEncrypt binary not found in ${LEBINARY} !"
  echo "You'll need to do one of the following:"
  echo "1) Change LEBINARY variable in this script"
  echo "2) Install LE manually or via your package manager and do #1"
  echo "3) Use the included get-letsencrypt.sh script to install it"
  exit 1
fi

if [[ ! -x $( which keytool ) ]]; then
  echo "Error: Java keytool binary not found."
  exit 1
fi

if [[ ! -x $( which openssl ) ]]; then
  echo "Error: OpenSSL binary not found."
  exit 1
fi

if [[ ! -z ${uselegacy} ]]; then
  osslopt=" -legacy"
else
  osslopt=""
fi

if [[ ! -z ${email} ]]; then
  email="--email ${email}"
else
  email=""
fi

if [[ ! -z ${userkeystore} ]]; then
  KEYSTORE="${userkeystore}"
fi

shift $((OPTIND -1))
for val in "${domains[@]}"; do
        DOMAINS="${DOMAINS} -d ${val} "
done

MAINDOMAIN=${domains[0]}

if [[ -z ${MAINDOMAIN} ]]; then
  echo "Error: At least one -d argument is required"
  usage
  exit 1
fi

if [[ ${renew} == "yes" ]]; then
  LEOPTIONS="${RENEWCERT}"
else
  LEOPTIONS="${email} ${DOMAINS} ${NEWCERT}"
fi

if [[ ${onlyinsert} != "yes" ]]; then
  echo "Firing up standalone authenticator on TCP port 80 and requesting cert..."
  ${LEBINARY} --agree-tos --standalone --preferred-challenges http ${LEOPTIONS}
fi

if [[ ${onlyinsert} != "yes" ]] && md5sum -c "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem.md5" &>/dev/null; then
  echo "Cert has not changed, not updating controller."
  exit 0
else
  echo "Cert has changed or -i option was used, updating controller..."
  TEMPFILE=$(mktemp)
  CATEMPFILE=$(mktemp)
  INTERMEDTEMPFILE=$(mktemp)

  # ISRG Root X1
  cat > "${CATEMPFILE}" <<'_EOF'
-----BEGIN CERTIFICATE-----
MIIFYDCCBEigAwIBAgIQQAF3ITfU6UK47naqPGQKtzANBgkqhkiG9w0BAQsFADA/
MSQwIgYDVQQKExtEaWdpdGFsIFNpZ25hdHVyZSBUcnVzdCBDby4xFzAVBgNVBAMT
DkRTVCBSb290IENBIFgzMB4XDTIxMDEyMDE5MTQwM1oXDTI0MDkzMDE4MTQwM1ow
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwggIiMA0GCSqGSIb3DQEB
AQUAA4ICDwAwggIKAoICAQCt6CRz9BQ385ueK1coHIe+3LffOJCMbjzmV6B493XC
ov71am72AE8o295ohmxEk7axY/0UEmu/H9LqMZshftEzPLpI9d1537O4/xLxIZpL
wYqGcWlKZmZsj348cL+tKSIG8+TA5oCu4kuPt5l+lAOf00eXfJlII1PoOK5PCm+D
LtFJV4yAdLbaL9A4jXsDcCEbdfIwPPqPrt3aY6vrFk/CjhFLfs8L6P+1dy70sntK
4EwSJQxwjQMpoOFTJOwT2e4ZvxCzSow/iaNhUd6shweU9GNx7C7ib1uYgeGJXDR5
bHbvO5BieebbpJovJsXQEOEO3tkQjhb7t/eo98flAgeYjzYIlefiN5YNNnWe+w5y
sR2bvAP5SQXYgd0FtCrWQemsAXaVCg/Y39W9Eh81LygXbNKYwagJZHduRze6zqxZ
Xmidf3LWicUGQSk+WT7dJvUkyRGnWqNMQB9GoZm1pzpRboY7nn1ypxIFeFntPlF4
FQsDj43QLwWyPntKHEtzBRL8xurgUBN8Q5N0s8p0544fAQjQMNRbcTa0B7rBMDBc
SLeCO5imfWCKoqMpgsy6vYMEG6KDA0Gh1gXxG8K28Kh8hjtGqEgqiNx2mna/H2ql
PRmP6zjzZN7IKw0KKP/32+IVQtQi0Cdd4Xn+GOdwiK1O5tmLOsbdJ1Fu/7xk9TND
TwIDAQABo4IBRjCCAUIwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYw
SwYIKwYBBQUHAQEEPzA9MDsGCCsGAQUFBzAChi9odHRwOi8vYXBwcy5pZGVudHJ1
c3QuY29tL3Jvb3RzL2RzdHJvb3RjYXgzLnA3YzAfBgNVHSMEGDAWgBTEp7Gkeyxx
+tvhS5B1/8QVYIWJEDBUBgNVHSAETTBLMAgGBmeBDAECATA/BgsrBgEEAYLfEwEB
ATAwMC4GCCsGAQUFBwIBFiJodHRwOi8vY3BzLnJvb3QteDEubGV0c2VuY3J5cHQu
b3JnMDwGA1UdHwQ1MDMwMaAvoC2GK2h0dHA6Ly9jcmwuaWRlbnRydXN0LmNvbS9E
U1RST09UQ0FYM0NSTC5jcmwwHQYDVR0OBBYEFHm0WeZ7tuXkAXOACIjIGlj26Ztu
MA0GCSqGSIb3DQEBCwUAA4IBAQAKcwBslm7/DlLQrt2M51oGrS+o44+/yQoDFVDC
5WxCu2+b9LRPwkSICHXM6webFGJueN7sJ7o5XPWioW5WlHAQU7G75K/QosMrAdSW
9MUgNTP52GE24HGNtLi1qoJFlcDyqSMo59ahy2cI2qBDLKobkx/J3vWraV0T9VuG
WCLKTVXkcGdtwlfFRjlBz4pYg1htmf5X6DYO8A4jqv2Il9DjXA6USbW1FzXSLr9O
he8Y4IWS6wY7bCkjCWDcRQJMEhg76fsO3txE+FiYruq9RUWhiF1myv4Q6W+CyBFC
Dfvp7OOGAN6dEOM4+qR9sdjoSYKEBpsr6GtPAQw4dy753ec5
-----END CERTIFICATE-----
_EOF

  # LE R3 Intermediary
  cat > "${INTERMEDTEMPFILE}" <<'_EOF'
-----BEGIN CERTIFICATE-----
MIIFFjCCAv6gAwIBAgIRAJErCErPDBinU/bWLiWnX1owDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMjAwOTA0MDAwMDAw
WhcNMjUwOTE1MTYwMDAwWjAyMQswCQYDVQQGEwJVUzEWMBQGA1UEChMNTGV0J3Mg
RW5jcnlwdDELMAkGA1UEAxMCUjMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
AoIBAQC7AhUozPaglNMPEuyNVZLD+ILxmaZ6QoinXSaqtSu5xUyxr45r+XXIo9cP
R5QUVTVXjJ6oojkZ9YI8QqlObvU7wy7bjcCwXPNZOOftz2nwWgsbvsCUJCWH+jdx
sxPnHKzhm+/b5DtFUkWWqcFTzjTIUu61ru2P3mBw4qVUq7ZtDpelQDRrK9O8Zutm
NHz6a4uPVymZ+DAXXbpyb/uBxa3Shlg9F8fnCbvxK/eG3MHacV3URuPMrSXBiLxg
Z3Vms/EY96Jc5lP/Ooi2R6X/ExjqmAl3P51T+c8B5fWmcBcUr2Ok/5mzk53cU6cG
/kiFHaFpriV1uxPMUgP17VGhi9sVAgMBAAGjggEIMIIBBDAOBgNVHQ8BAf8EBAMC
AYYwHQYDVR0lBBYwFAYIKwYBBQUHAwIGCCsGAQUFBwMBMBIGA1UdEwEB/wQIMAYB
Af8CAQAwHQYDVR0OBBYEFBQusxe3WFbLrlAJQOYfr52LFMLGMB8GA1UdIwQYMBaA
FHm0WeZ7tuXkAXOACIjIGlj26ZtuMDIGCCsGAQUFBwEBBCYwJDAiBggrBgEFBQcw
AoYWaHR0cDovL3gxLmkubGVuY3Iub3JnLzAnBgNVHR8EIDAeMBygGqAYhhZodHRw
Oi8veDEuYy5sZW5jci5vcmcvMCIGA1UdIAQbMBkwCAYGZ4EMAQIBMA0GCysGAQQB
gt8TAQEBMA0GCSqGSIb3DQEBCwUAA4ICAQCFyk5HPqP3hUSFvNVneLKYY611TR6W
PTNlclQtgaDqw+34IL9fzLdwALduO/ZelN7kIJ+m74uyA+eitRY8kc607TkC53wl
ikfmZW4/RvTZ8M6UK+5UzhK8jCdLuMGYL6KvzXGRSgi3yLgjewQtCPkIVz6D2QQz
CkcheAmCJ8MqyJu5zlzyZMjAvnnAT45tRAxekrsu94sQ4egdRCnbWSDtY7kh+BIm
lJNXoB1lBMEKIq4QDUOXoRgffuDghje1WrG9ML+Hbisq/yFOGwXD9RiX8F6sw6W4
avAuvDszue5L3sz85K+EC4Y/wFVDNvZo4TYXao6Z0f+lQKc0t8DQYzk1OXVu8rp2
yJMC6alLbBfODALZvYH7n7do1AZls4I9d1P4jnkDrQoxB3UqQ9hVl3LEKQ73xF1O
yK5GhDDX8oVfGKF5u+decIsH4YaTw7mP3GFxJSqv3+0lUFJoi5Lc5da149p90Ids
hCExroL1+7mryIkXPeFM5TgO9r0rvZaBFOvV2z0gp35Z0+L4WPlbuEjN/lxPFin+
HlUjr8gRsI3qfJOQFy/9rKIJR0Y/8Omwt/8oTWgy1mdeHmmjk7j1nYsvC9JSQ6Zv
MldlTTKB3zhThV1+XWYp6rjd5JW1zbVWEkLNxE7GJThEUG3szgBVGP7pSWTUTsqX
nLRbwHOoq7hHwg==
-----END CERTIFICATE-----
_EOF

  md5sum "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem" > "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem.md5"
  #echo "Using openssl to prepare certificate..."
  #cat "/etc/letsencrypt/live/${MAINDOMAIN}/chain.pem" >> "${CATEMPFILE}"
  openssl pkcs12 -export ${osslopt} -passout pass:aircontrolenterprise \
          -in "/etc/letsencrypt/live/${MAINDOMAIN}/fullchain.pem" \
          -inkey "/etc/letsencrypt/live/${MAINDOMAIN}/privkey.pem" \
          -out "${TEMPFILE}" -name unifi
  
  echo "Stopping Unifi controller..."
  service unifi stop
  
  echo "Removing existing certificates from Unifi protected keystore..."
  keytool -delete -alias unifi -keystore "${KEYSTORE}" \
          -deststorepass aircontrolenterprise -noprompt
  keytool -delete -alias root -keystore "${KEYSTORE}" \
          -deststorepass aircontrolenterprise -noprompt
  keytool -delete -alias intermediate1 -keystore "${KEYSTORE}" \
          -deststorepass aircontrolenterprise -noprompt
  
  echo "Importing root LE CA cert and intermediaries..."
  keytool -import -trustcacerts -alias root -file "${CATEMPFILE}" \
          -storepass aircontrolenterprise -keystore "${KEYSTORE}" -noprompt
          
  keytool -import -trustcacerts -alias intermediate1 -file "${INTERMEDTEMPFILE}" \
          -storepass aircontrolenterprise -keystore "${KEYSTORE}" -noprompt


  echo "Importing certificate into Unifi keystore..."
  keytool -importkeystore \
          -deststorepass aircontrolenterprise \
          -destkeypass aircontrolenterprise \
          -destkeystore ${KEYSTORE} \
          -srckeystore "${TEMPFILE}" -srcstoretype PKCS12 \
          -srcstorepass aircontrolenterprise \
          -alias unifi -noprompt
  rm -f "${TEMPFILE}" "${CATEMPFILE}" "${INTERMEDTEMPFILE}"

  echo "Starting Unifi controller..."
  service unifi start

  echo "Done!"
fi
