// Command weavemanifest generates, signs and verifies Weave channel
// manifests and their two-tier signing chain: an offline root key
// endorses named signing keys; signing keys sign channel manifests.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
)

const usage = `weavemanifest — channel manifest tooling

Usage:
  weavemanifest keygen <key-id> <out-prefix>
      Generate an Ed25519 keypair: <out-prefix>.pub (JSON public key) and
      <out-prefix>.key (base64 private key — guard it; the root key stays
      offline).

  weavemanifest endorse <root.key> <signing.pub>
      Root-endorse a signing key: writes <signing.pub>.sig.

  weavemanifest sign <signing.key> <file>
      Sign a file with a signing key: writes <file>.sig.

  weavemanifest verify <root.pub> <signing.pub> <file>
      Verify the full chain: root endorsement of the signing key, then the
      signing key's signature over the file. Exits non-zero on any break.
`

func main() {
	if len(os.Args) < 2 {
		fail(usage)
	}
	var err error
	switch os.Args[1] {
	case "keygen":
		err = keygen(os.Args[2:])
	case "endorse":
		err = signFile(os.Args[2:], true)
	case "sign":
		err = signFile(os.Args[2:], false)
	case "verify":
		err = verify(os.Args[2:])
	case "generate", "promote", "pin":
		err = fmt.Errorf("%s: assembled by CI in the module publish pipeline; not yet a local verb", os.Args[1])
	default:
		fail(usage)
	}
	if err != nil {
		fail("weavemanifest: %v\n", err)
	}
}

type publicKeyFile struct {
	Schema    int    `json:"schema"`
	KeyID     string `json:"key_id"`
	PublicKey string `json:"public_key"`
}

type privateKeyFile struct {
	Schema     int    `json:"schema"`
	KeyID      string `json:"key_id"`
	PrivateKey string `json:"private_key"`
}

type signatureFile struct {
	Schema    int    `json:"schema"`
	KeyID     string `json:"key_id"`
	Signature string `json:"signature"`
}

func keygen(args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("keygen <key-id> <out-prefix>")
	}
	id, prefix := args[0], args[1]
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return err
	}
	if err := writeJSON(prefix+".pub", 0o644, publicKeyFile{
		Schema: 1, KeyID: id, PublicKey: base64.StdEncoding.EncodeToString(pub),
	}); err != nil {
		return err
	}
	if err := writeJSON(prefix+".key", 0o600, privateKeyFile{
		Schema: 1, KeyID: id, PrivateKey: base64.StdEncoding.EncodeToString(priv),
	}); err != nil {
		return err
	}
	fmt.Printf("generated %s.pub and %s.key (key id %q)\n", prefix, prefix, id)
	return nil
}

// signFile signs args[1] with the private key at args[0]. endorse only
// differs in intent (the signed file is a signing public key).
func signFile(args []string, endorse bool) error {
	if len(args) != 2 {
		if endorse {
			return fmt.Errorf("endorse <root.key> <signing.pub>")
		}
		return fmt.Errorf("sign <signing.key> <file>")
	}
	priv, keyID, err := readPrivate(args[0])
	if err != nil {
		return err
	}
	data, err := os.ReadFile(args[1])
	if err != nil {
		return err
	}
	sig := ed25519.Sign(priv, data)
	out := args[1] + ".sig"
	if err := writeJSON(out, 0o644, signatureFile{
		Schema: 1, KeyID: keyID, Signature: base64.StdEncoding.EncodeToString(sig),
	}); err != nil {
		return err
	}
	fmt.Printf("signed %s → %s (key %q)\n", args[1], out, keyID)
	return nil
}

func verify(args []string) error {
	if len(args) != 3 {
		return fmt.Errorf("verify <root.pub> <signing.pub> <file>")
	}
	rootRaw, _, err := readPublic(args[0])
	if err != nil {
		return err
	}
	signingBytes, err := os.ReadFile(args[1])
	if err != nil {
		return err
	}
	endorsement, endorsementSig, err := readSig(args[1] + ".sig")
	if err != nil {
		return fmt.Errorf("endorsement: %w", err)
	}
	if endorsement != "root" {
		return fmt.Errorf("signing key endorsed by %q, not root", endorsement)
	}
	if !ed25519.Verify(rootRaw, signingBytes, endorsementSig) {
		return fmt.Errorf("signing key endorsement invalid")
	}
	signingRaw, signingID, err := readPublic(args[1])
	if err != nil {
		return err
	}
	fileBytes, err := os.ReadFile(args[2])
	if err != nil {
		return err
	}
	sigID, sigRaw, err := readSig(args[2] + ".sig")
	if err != nil {
		return err
	}
	if sigID != signingID {
		return fmt.Errorf("file signed by %q but signing key is %q", sigID, signingID)
	}
	if !ed25519.Verify(signingRaw, fileBytes, sigRaw) {
		return fmt.Errorf("file signature invalid")
	}
	fmt.Printf("OK: %s verifies via %s under root\n", args[2], signingID)
	return nil
}

func readPrivate(path string) (ed25519.PrivateKey, string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, "", err
	}
	var pk privateKeyFile
	if err := json.Unmarshal(data, &pk); err != nil {
		return nil, "", err
	}
	raw, err := base64.StdEncoding.DecodeString(pk.PrivateKey)
	if err != nil || len(raw) != ed25519.PrivateKeySize {
		return nil, "", fmt.Errorf("%s: not a valid private key", path)
	}
	return ed25519.PrivateKey(raw), pk.KeyID, nil
}

func readPublic(path string) (ed25519.PublicKey, string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, "", err
	}
	var pk publicKeyFile
	if err := json.Unmarshal(data, &pk); err != nil {
		return nil, "", err
	}
	raw, err := base64.StdEncoding.DecodeString(pk.PublicKey)
	if err != nil || len(raw) != ed25519.PublicKeySize {
		return nil, "", fmt.Errorf("%s: not a valid public key", path)
	}
	return ed25519.PublicKey(raw), pk.KeyID, nil
}

func readSig(path string) (string, []byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", nil, err
	}
	var sig signatureFile
	if err := json.Unmarshal(data, &sig); err != nil {
		return "", nil, err
	}
	raw, err := base64.StdEncoding.DecodeString(sig.Signature)
	if err != nil || len(raw) != ed25519.SignatureSize {
		return "", nil, fmt.Errorf("%s: not a valid signature", path)
	}
	return sig.KeyID, raw, nil
}

func writeJSON(path string, mode os.FileMode, v any) error {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), mode)
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format, args...)
	os.Exit(1)
}
