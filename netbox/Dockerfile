# =============================================================
# NetBox Custom Image
# Base: netboxcommunity/netbox:v4.5
# Adds: netbox_unifi_sync plugin
#
# The plugin must be installed in the same image used by both
# the netbox and netbox-worker containers. Using the stock
# image without the plugin will cause worker sync jobs to fail.
# =============================================================

ARG NETBOX_VERSION=v4.5
FROM netboxcommunity/netbox:${NETBOX_VERSION}

# Copy local_requirements.txt into the image so that the plugin is reinstalled automatically if the base image is updated
COPY local_requirements.txt /opt/netbox/local_requirements.txt

# Install the UniFi sync plugin
# This also installs all plugin dependencies into the NetBox venv
RUN /opt/netbox/venv/bin/pip install \
    --no-cache-dir \
    -r /opt/netbox/local_requirements.txt

# Trust Eirdom Active Directory CA
COPY eirdom-ldap-ca-bundle.pem /usr/local/share/ca-certificates/eirdom-ldap-ca.crt

RUN update-ca-certificates
