package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/charmbracelet/lipgloss"
)

func TestReplaceImagePathsUsesStableTokens(t *testing.T) {
	dir := t.TempDir()
	image := filepath.Join(dir, "dragged image.png")
	if err := osWriteFile(image, []byte("png"), 0o600); err != nil {
		t.Fatal(err)
	}

	m := initialModel(config{claudeCount: 1, codexCount: 1, useAIName: true})
	replaced, changed := m.replaceImagePaths(`look at "` + image + `" and ` + shellEscape(image))
	if !changed {
		t.Fatal("expected image path replacement")
	}
	if replaced != "look at [Image #1] and [Image #1]" {
		t.Fatalf("unexpected replacement: %q", replaced)
	}
	if len(m.images) != 1 {
		t.Fatalf("expected one attachment, got %d", len(m.images))
	}
	if m.images[0].Token != "[Image #1]" {
		t.Fatalf("unexpected token: %q", m.images[0].Token)
	}
}

func TestRenderInputFillsEveryLine(t *testing.T) {
	m := initialModel(config{claudeCount: 1, codexCount: 1, useAIName: true})
	m.resize(120, 40)

	out := m.renderInput(72)
	lines := strings.Split(out, "\n")
	if len(lines) != m.textarea.Height() {
		t.Fatalf("expected %d lines, got %d", m.textarea.Height(), len(lines))
	}
	for index, line := range lines {
		if width := lipgloss.Width(line); width != 72 {
			t.Fatalf("line %d width = %d, want 72", index, width)
		}
	}
}

func osWriteFile(name string, data []byte, perm uint32) error {
	return os.WriteFile(name, data, os.FileMode(perm))
}

func shellEscape(path string) string {
	out := make([]rune, 0, len(path))
	for _, r := range path {
		if r == ' ' {
			out = append(out, '\\', ' ')
		} else {
			out = append(out, r)
		}
	}
	return string(out)
}
