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

# Install the UniFi sync plugin
# This also installs all plugin dependencies into the NetBox venv
RUN /opt/netbox/venv/bin/pip install netbox-unifi-sync

# Copy plugin requirements into local_requirements.txt so the
# plugin is reinstalled automatically if the base image is updated
RUN echo "netbox-unifi-sync" >> /opt/netbox/local_requirements.txt
