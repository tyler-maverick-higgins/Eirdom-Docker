# =============================================================
# NetBox Configuration
# Eirdom Infrastructure
# =============================================================
# This file is mounted into the NetBox container at:
# /etc/netbox/config/configuration.py
# =============================================================

import os

# =============================================================
# REQUIRED SETTINGS
# =============================================================

ALLOWED_HOSTS = [
    os.environ.get('NETBOX_ALLOWED_HOST', 'netbox.eirdom.homes'),
    'localhost',
    '127.0.0.1',
]

DATABASE = {
    'NAME': os.environ.get('NETBOX_DB_NAME', 'netbox'),
    'USER': os.environ.get('NETBOX_DB_USER', 'netbox'),
    'PASSWORD': os.environ.get('NETBOX_DB_PASSWORD', ''),
    'HOST': 'netbox-postgres',
    'PORT': '',
    'CONN_MAX_AGE': 300,
}

REDIS = {
    'tasks': {
        'HOST': 'netbox-redis',
        'PORT': 6379,
        'PASSWORD': os.environ.get('NETBOX_REDIS_PASSWORD', ''),
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': 'netbox-redis',
        'PORT': 6379,
        'PASSWORD': os.environ.get('NETBOX_REDIS_PASSWORD', ''),
        'DATABASE': 1,
        'SSL': False,
    },
}

SECRET_KEY = os.environ.get('NETBOX_SECRET_KEY', '')

# =============================================================
# OPTIONAL SETTINGS
# =============================================================

ADMINS = []

BASE_PATH = ''

CHANGELOG_RETENTION = 90

EMAIL = {
    'SERVER': os.environ.get('SMTP_HOST', 'smtp.gmail.com'),
    'PORT': int(os.environ.get('SMTP_PORT', 587)),
    'USERNAME': os.environ.get('SMTP_USER', ''),
    'PASSWORD': os.environ.get('SMTP_PASSWORD', ''),
    'USE_SSL': False,
    'USE_TLS': True,
    'TIMEOUT': 10,
    'FROM_EMAIL': os.environ.get('SMTP_FROM_EMAIL', ''),
}

LOGIN_REQUIRED = True

MEDIA_ROOT = '/opt/netbox/netbox/media'

METRICS_ENABLED = False

PAGINATE_COUNT = 25

PREFER_IPV4 = True

TIME_ZONE = os.environ.get('TZ', 'America/Chicago')

DATE_FORMAT = 'N j, Y'
SHORT_DATE_FORMAT = 'm/d/Y'
TIME_FORMAT = 'g:i a'
DATETIME_FORMAT = 'N j, Y g:i a'
SHORT_DATETIME_FORMAT = 'm/d/Y H:i'

# =============================================================
# ACTIVE DIRECTORY LDAP AUTHENTICATION
# Authenticates against EIRDOM-DC-01 directly
# No Authentik ForwardAuth — NetBox handles its own auth
# =============================================================

REMOTE_AUTH_BACKEND = 'netbox.authentication.LDAPBackend'

import ldap
from django_auth_ldap.config import LDAPSearch, GroupOfNamesType, NestedActiveDirectoryGroupType

# Configure LDAP to trust the Eirdom Active Directory CA
ldap.set_option(
    ldap.OPT_X_TLS_CACERTFILE,
    "/etc/ssl/certs/ca-certificates.crt",
)

# LDAP server
AUTH_LDAP_SERVER_URI = os.environ.get('LDAP_SERVER', 'ldaps://10.1.10.10')

# Bind account — dedicated service account in AD
# CN=netbox-svc,OU=Service Accounts,OU=Eirdom,DC=ad,DC=eirdom,DC=homes
AUTH_LDAP_BIND_DN = os.environ.get('LDAP_BIND_DN', '')
AUTH_LDAP_BIND_PASSWORD = os.environ.get('LDAP_BIND_PASSWORD', '')

# TLS — use STARTTLS on port 389
AUTH_LDAP_START_TLS = False

# User search
AUTH_LDAP_USER_SEARCH = LDAPSearch(
    'OU=Users,OU=Eirdom,DC=ad,DC=eirdom,DC=homes',
    ldap.SCOPE_SUBTREE,
    '(sAMAccountName=%(user)s)',
)

# Map AD attributes to NetBox user fields
AUTH_LDAP_USER_ATTR_MAP = {
    'first_name': 'givenName',
    'last_name': 'sn',
    'email': 'mail',
}

# Group search — used for NetBox role assignment
AUTH_LDAP_GROUP_SEARCH = LDAPSearch(
    'OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes',
    ldap.SCOPE_SUBTREE,
    '(objectClass=group)',
)

AUTH_LDAP_GROUP_TYPE = NestedActiveDirectoryGroupType()

# Require membership in this AD group to log in to NetBox
# Create this group in AD: CN=NetBox-Users,OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes
AUTH_LDAP_REQUIRE_GROUP = 'CN=NetBox-Users,OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes'

# Map AD groups to NetBox permissions
# Create these groups in AD as needed
AUTH_LDAP_USER_FLAGS_BY_GROUP = {
    # Members of NetBox-Admins get full superuser access
    'is_active': 'CN=NetBox-Users,OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes',
    'is_staff': 'CN=NetBox-Staff,OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes',
    'is_superuser': 'CN=NetBox-Admins,OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes',
}

AUTH_LDAP_MIRROR_GROUPS = True

# =============================================================
# PLUGINS
# =============================================================

PLUGINS = [
    'netbox_unifi_sync',
]

PLUGINS_CONFIG = {
    # netbox_unifi_sync is configured entirely through the NetBox
    # UI after initial setup — no hardcoded credentials here.
    # Navigate to: Plugins → UniFi Sync → Settings
    # Add your UniFi controller and credentials through the UI.
    # Credentials are stored encrypted in the NetBox database.
    'netbox_unifi_sync': {},
}