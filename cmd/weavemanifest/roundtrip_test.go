package main

import (
	"os"
	"path/filepath"
	"testing"
)

// TestSignVerifyGoldenRoundTrip proves the tool's own output verifies: a
// freshly generated root endorses a signing key, the signing key signs a
// manifest, and verify accepts the whole chain. Tampering with the signed
// manifest afterwards must make verify fail. This is the end-to-end contract
// the fleet depends on — a manifest weavemanifest signs is one core accepts.
func TestSignVerifyGoldenRoundTrip(t *testing.T) {
	dir := t.TempDir()
	root := filepath.Join(dir, "root")
	signing := filepath.Join(dir, "signing")
	manifestPath := filepath.Join(dir, "manifest.json")

	// key ids: verify requires the endorsement to come from key id "root".
	if err := keygen([]string{"root", root}); err != nil {
		t.Fatalf("keygen root: %v", err)
	}
	if err := keygen([]string{"signing-2026", signing}); err != nil {
		t.Fatalf("keygen signing: %v", err)
	}

	manifestJSON := []byte(`{"schema":1,"channel":"stable","generated_at":"2026-08-10T00:00:00Z","protocol":{"min":1,"max":1},"core":{"version":"0.1.0","artifacts":[]},"modules":[]}`)
	if err := os.WriteFile(manifestPath, manifestJSON, 0o644); err != nil {
		t.Fatal(err)
	}

	// root endorses the signing public key; signing key signs the manifest.
	if err := signFile([]string{root + ".key", signing + ".pub"}, true); err != nil {
		t.Fatalf("endorse: %v", err)
	}
	if err := signFile([]string{signing + ".key", manifestPath}, false); err != nil {
		t.Fatalf("sign manifest: %v", err)
	}

	// Golden path: the full chain verifies.
	if err := verify([]string{root + ".pub", signing + ".pub", manifestPath}); err != nil {
		t.Fatalf("verify of a freshly signed manifest failed: %v", err)
	}

	// Tamper: a single flipped byte in the signed manifest must be rejected.
	tampered := append([]byte{}, manifestJSON...)
	tampered[10] ^= 0xff
	if err := os.WriteFile(manifestPath, tampered, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := verify([]string{root + ".pub", signing + ".pub", manifestPath}); err == nil {
		t.Fatal("verify accepted a tampered manifest")
	}
}
