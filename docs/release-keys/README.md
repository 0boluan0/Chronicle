# Clean-account release attestation key

Public publication requires a reviewed Ed25519 public key at:

`docs/release-keys/clean-account-ed25519-public.pem`

That production public key is intentionally not bootstrapped by CI. Until an independently generated key is reviewed and committed at the exact path above, `publish-release.yml` fails closed. Never commit the corresponding private key, a production signature, or a manufactured production payload.

The private key belongs only on the isolated clean-account test system. After the real published-`v1.0.5` to signed-candidate exercise, that system creates one compact canonical JSON payload (UTF-8, object keys recursively sorted lexicographically, no insignificant whitespace, exactly one trailing LF) and signs those exact bytes with Ed25519. The protected `chronicle-release-publish` environment receives two separate base64 secrets:

- `CLEAN_ACCOUNT_ATTESTATION_PAYLOAD_BASE64`
- `CLEAN_ACCOUNT_ATTESTATION_SIGNATURE_BASE64`

The payload schema is `3` and binds the repository, issue/expiry window (at most 24 hours), clean-account identity, all required checks, the actual published `v1.0.5` release ID and DMG asset ID/name/size/SHA-256, and the candidate tag/source plus unique Actions artifact ID/name/archive SHA-256, staging run ID/attempt, canonical-manifest SHA-256, and DMG name/size/SHA-256. Obtain the artifact ID and archive digest from the successful staging run's GitHub Actions artifacts API only after confirming the artifact is unique and unexpired; the publication workflow independently resolves and checks the same values, including the artifact's workflow-run identity, and downloads it by ID. The candidate is intentionally identified before any GitHub Release exists. The expected nonce is:

`chronicle:<owner/repo>:<staging-run-id>:<staging-run-attempt>:<candidate-artifact-id>:<candidate-artifact-name>:<candidate-manifest-sha256>`

Example signing commands on the isolated machine (paths are illustrative):

```sh
openssl pkeyutl -sign -inkey /secure/offline/clean-account-ed25519-private.pem \
  -rawin -in clean-account-payload.json -out clean-account-payload.sig
base64 < clean-account-payload.json
base64 < clean-account-payload.sig
```

The offline fixture suite generates a temporary keypair under its temporary directory. Those fixture keys and payloads are never production evidence.
