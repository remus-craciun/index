package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadDotEnv(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".env")
	content := "# comment\n\nexport A_PLAIN=one\nA_QUOTED=\"two words\"\nA_INLINE=three # note\nA_EMPTY=\nA_PRESET=from-file\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("A_PRESET", "from-env")
	for _, k := range []string{"A_PLAIN", "A_QUOTED", "A_INLINE", "A_EMPTY"} {
		t.Setenv(k, "") // registers cleanup
		os.Unsetenv(k)
	}

	if err := loadDotEnv(path); err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"A_PLAIN": "one", "A_QUOTED": "two words", "A_INLINE": "three", "A_EMPTY": "", "A_PRESET": "from-env",
	}
	for k, v := range want {
		if got := os.Getenv(k); got != v {
			t.Errorf("%s = %q, want %q", k, got, v)
		}
	}

	if err := loadDotEnv(filepath.Join(t.TempDir(), "missing")); err != nil {
		t.Fatalf("missing file should be ignored: %v", err)
	}
}
