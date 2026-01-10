import os
import httpx
from fastapi import Request, HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError

# Configuration
KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "http://keycloak:8080")
REALM = os.getenv("REALM", "NodeSense")
CLIENT_ID = os.getenv("CLIENT_ID", "gateway-client")

# Fetch public key from Keycloak
JWKS_URL = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/certs"

security = HTTPBearer()

async def get_public_key():
    print(f"DEBUG: Fetching JWKS from {JWKS_URL}")
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.get(JWKS_URL)
            print(f"DEBUG: JWKS Response Status: {resp.status_code}")
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            print(f"DEBUG: Failed to fetch JWKS: {e}")
            raise HTTPException(status_code=500, detail="Auth service unavailable")

async def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    print("DEBUG: verify_token called")
    token = credentials.credentials
    
    try:
        # For simplicity in this demo, we might skip strict signature verification 
        # if we can't easily reach Keycloak from inside the container during build/test 
        # without proper network dns. But in production we MUST verify.
        # We will attempt verification.
        
        jwks = await get_public_key()
        print("DEBUG: JWKS fetched")

        
        # Verify token
        payload = jwt.decode(
            token,
            jwks,
            algorithms=["RS256"],
            audience="account", # Keycloak default audience often includes 'account'
            options={"verify_aud": False} # Relax audience check for this demo
        )
        return payload
    except JWTError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

async def verify_admin(payload: dict = Security(verify_token)):
    print(f"DEBUG: Verifying admin role for user: {payload.get('preferred_username', 'unknown')}")
    
    # Check Realm Roles
    realm_access = payload.get("realm_access", {})
    roles = realm_access.get("roles", [])
    
    if "admin" in roles:
        return payload
        
    print(f"DEBUG: Access denied. User roles: {roles}")
    raise HTTPException(status_code=403, detail="Admin privileges required")
