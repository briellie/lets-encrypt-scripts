#!/usr/bin/env bash
# Modified script from here: https://github.com/FarsetLabs/letsencrypt-helper-scripts/blob/master/letsencrypt-unifi.sh
# Modified by: Brielle Bruns <bruns@2mbit.com>
# Download URL: https://source.sosdg.org/brielle/lets-encrypt-scripts
# Version: 1.9
# Last Changed: 09/22/2021
# 02/02/2016: Fixed some errors with key export/import, removed lame docker requirements
# 02/27/2016: More verbose progress report
# 03/08/2016: Add renew option, reformat code, command line options
# 03/24/2016: More sanity checking, embedding cert
# 10/23/2017: Apparently don't need the ace.jar parts, so disable them
# 02/04/2018: LE disabled tls-sni-01, so switch to just tls-sni, as certbot 0.22 and later automatically fall back to http/80 for auth
# 05/29/2018: Integrate patch from Donald Webster <fryfrog[at]gmail.com> to cleanup and improve tests
# 09/26/2018: Change from TLS to HTTP authenticator
# 09/22/2021: Update root certs

# Location of LetsEncrypt binary we use.  Leave unset if you want to let it find automatically
#LEBINARY="/usr/src/letsencrypt/certbot-auto"

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

function usage() {
  echo "Usage: $0 -d <domain> [-e <email>] [-r] [-i]"
  echo "  -d <domain>: The domain name to use."
  echo "  -e <email>: Email address to use for certificate."
  echo "  -r: Renew domain."
  echo "  -i: Insert only, use to force insertion of certificate."
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

  # ISRG Root X1 and LE R3 certs to inject as well
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

  md5sum "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem" > "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem.md5"
  echo "Using openssl to prepare certificate..."
  cat "/etc/letsencrypt/live/${MAINDOMAIN}/chain.pem" >> "${CATEMPFILE}"
  openssl pkcs12 -export  -passout pass:aircontrolenterprise \
          -in "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem" \
          -inkey "/etc/letsencrypt/live/${MAINDOMAIN}/privkey.pem" \
          -out "${TEMPFILE}" -name unifi \
          -CAfile "${CATEMPFILE}" -caname root

  echo "Stopping Unifi controller..."
  service unifi stop

  echo "Removing existing certificate from Unifi protected keystore..."
  keytool -delete -alias unifi -keystore /usr/lib/unifi/data/keystore \
          -deststorepass aircontrolenterprise

  echo "Inserting certificate into Unifi keystore..."
  keytool -trustcacerts -importkeystore \
          -deststorepass aircontrolenterprise \
          -destkeypass aircontrolenterprise \
          -destkeystore /usr/lib/unifi/data/keystore \
          -srckeystore "${TEMPFILE}" -srcstoretype PKCS12 \
          -srcstorepass aircontrolenterprise \
          -alias unifi
  rm -f "${TEMPFILE}" "${CATEMPFILE}"

  echo "Starting Unifi controller..."
  service unifi start

  echo "Done!"
fi
