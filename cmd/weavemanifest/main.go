// Command weavemanifest generates, signs, verifies, promotes and pins Weave
// channel manifests. Implemented in milestone M6; the verbs below are the
// contract.
package main

import (
	"fmt"
	"os"
)

const usage = `weavemanifest — channel manifest tooling

Usage:
  weavemanifest generate   assemble a channel manifest from module sidecars
  weavemanifest sign       sign a manifest with a signing key
  weavemanifest verify     verify a manifest against the signing chain
  weavemanifest promote    update the rolling channel with a new release
  weavemanifest pin        snapshot the rolling channel as an immutable pin
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	switch os.Args[1] {
	case "generate", "sign", "verify", "promote", "pin":
		fmt.Fprintf(os.Stderr, "weavemanifest %s: not implemented until milestone M6\n", os.Args[1])
		os.Exit(1)
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
}
