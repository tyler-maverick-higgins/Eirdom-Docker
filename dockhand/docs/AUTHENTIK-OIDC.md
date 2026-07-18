# Authentik OIDC for Dockhand

Dockhand supports any OIDC-compliant provider. Configure OIDC in the Dockhand UI
rather than placing the client secret in the Compose repository.

## Authentik application

Create an OAuth2/OpenID Provider and application with these values:

```text
Application name: Eirdom Dockhand
Client type: Confidential
Redirect URI: https://dockhand.eirdom.homes/api/auth/oidc/callback
Scopes: openid profile email
```

Create or map an Authentik group for administrators, for example:

```text
Eirdom-Dockhand-Admins
```

Ensure the OIDC token includes the group claim when using automatic admin
mapping.

## Dockhand provider settings

In **Settings → Authentication → SSO**, add:

```text
Name: Authentik
Issuer URL: https://auth.eirdom.homes/application/o/dockhand/
Client ID: <from Authentik>
Client secret: <from Authentik>
Redirect URI: https://dockhand.eirdom.homes/api/auth/oidc/callback
Scopes: openid profile email
Username claim: preferred_username
Email claim: email
Display-name claim: name
```

The exact issuer slug must match the Authentik provider's discovery URL. Verify
it by opening:

```text
https://auth.eirdom.homes/application/o/dockhand/.well-known/openid-configuration
```

## Safe rollout

1. Keep the local break-glass administrator enabled.
2. Test OIDC in an incognito browser.
3. Verify the OIDC user receives administrator access.
4. Test sign-out and sign-in again.
5. Only then consider setting:

```text
DOCKHAND_DISABLE_LOCAL_LOGIN=true
```

Keeping local login available is recommended for disaster recovery unless the
risk is explicitly accepted and a tested alternate recovery path exists.
