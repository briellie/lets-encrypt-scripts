#!/usr/bin/env bash
# Modified script from here: https://github.com/FarsetLabs/letsencrypt-helper-scripts/blob/master/letsencrypt-unifi.sh
# Modified by: Brielle Bruns <bruns@2mbit.com>
# Download URL: https://source.sosdg.org/brielle/lets-encrypt-scripts
# Version: 1.92
# Last Changed: 10/10/2021
# 02/02/2016: Fixed some errors with key export/import, removed lame docker requirements
# 02/27/2016: More verbose progress report
# 03/08/2016: Add renew option, reformat code, command line options
# 03/24/2016: More sanity checking, embedding cert
# 10/23/2017: Apparently don't need the ace.jar parts, so disable them
# 02/04/2018: LE disabled tls-sni-01, so switch to just tls-sni, as certbot 0.22 and later automatically fall back to http/80 for auth
# 05/29/2018: Integrate patch from Donald Webster <fryfrog[at]gmail.com> to cleanup and improve tests
# 09/26/2018: Change from TLS to HTTP authenticator
# 09/22/2021: Update root certs
# 10/10/2021: Split out import process for root certs

# Location of LetsEncrypt binary we use.  Leave unset if you want to let it find automatically
#LEBINARY="/usr/src/letsencrypt/certbot-auto"

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

KEYSTORE=/usr/lib/unifi/data/keystore


function usage() {
  echo "Usage: $0 -d <domain> [-e <email>] [-r] [-i]"
  echo "  -d <domain>: The domain name to use."
  echo "  -e <email>: Email address to use for certificate."
  echo "  -r: Renew domain."
  echo "  -i: Insert only, use to force insertion of certificate."
  echo "  -a: use ace.jar for insert instead of keytool."
}

while getopts "hird:e:" opt; do
  case $opt in
    i) onlyinsert="yes";;
    r) renew="yes";;
    d) domains+=("$OPTARG");;
    e) email="$OPTARG";;
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

if [[ ! -z ${email} ]]; then
  email="--email ${email}"
else
  email=""
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
  ${LEBINARY} --server https://acme-v02.api.letsencrypt.org/directory \
              --agree-tos --standalone --preferred-challenges http ${LEOPTIONS}
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
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
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
  openssl pkcs12 -export  -passout pass:aircontrolenterprise \
          -in "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem" \
          -inkey "/etc/letsencrypt/live/${MAINDOMAIN}/privkey.pem" \
          -out "${TEMPFILE}" -name unifi
  
  echo "Stopping Unifi controller..."
  service unifi stop
  
  echo "Importing root LE CA cert and intermediaries..."
  keytool -import -trustcacerts -alias root -file "${CATEMPFILE}" \
          -storepass aircontrolenterprise -keystore "${KEYSTORE}" -noprompt
          
  keytool -import -trustcacerts -alias intermediate1 -file "${INTERMEDTEMPFILE}" \
          -storepass aircontrolenterprise -keystore "${KEYSTORE}" -noprompt


  #echo "Removing existing certificate from Unifi protected keystore..."
  #keytool -delete -alias unifi -keystore /usr/lib/unifi/data/keystore \
  #        -deststorepass aircontrolenterprise

  echo "Importing certificate into Unifi keystore..."
  keytool -importkeystore \
          -deststorepass aircontrolenterprise \
          -destkeypass aircontrolenterprise \
          -destkeystore /usr/lib/unifi/data/keystore \
          -srckeystore "${TEMPFILE}" -srcstoretype PKCS12 \
          -srcstorepass aircontrolenterprise \
          -alias unifi -noprompt
  rm -f "${TEMPFILE}" "${CATEMPFILE}" "${INTERMEDTEMPFILE}"

  echo "Starting Unifi controller..."
  service unifi start

  echo "Done!"
fi
