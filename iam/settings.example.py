import os

WEB_PORT = 4837
MIN_PORT = 22000
MIN_SUBUID = 10000000
DB_NAME = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'iam.db')
IDENTITY_FILE = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'iam_id_rsa')
LDAP_HOST = '172.16.8.68'
LDAP_DOMAIN = 'apexlab.org'
LDAP_BASE = ['dc=apexlab', 'dc=org']
LDAP_IAM_USER = 'iam@apexlab.org'
LDAP_IAM_PASS = 'iam_password'

SERVERS = {
    'gpu2': '172.16.2.235',
    'gpu3': '172.16.2.237',
    'gpu4': '172.16.2.238',
    'gpu5': '172.16.2.239',
    'gpu6': '172.16.2.240',
    'gpu7': '172.16.2.241',
    'gpu8': '172.16.2.242',
    'gpu9': '172.16.2.243',
    'gpu10': '172.16.2.244',
    'gpu11': '172.16.2.245',
    'gpu12': '172.16.2.246',
    'gpu13': '172.16.2.247',
    'gpu14': '172.16.2.248',
    'gpu15': '172.16.2.249',
    'gpu16': '172.16.2.250',
    'gpu17': '172.16.2.251',
    'gpu18': '172.16.2.252',
}
