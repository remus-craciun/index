// Package config loads service configuration from the environment.
package config

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
)

type Config struct {
	Port         string
	DBPath       string
	JWTSecret    []byte
	GeminiAPIKey string
	GeminiModel  string
	CORSOrigins  []string
	AccessTTL    time.Duration
	RefreshTTL   time.Duration
}

// Load reads configuration from environment variables, filling in any that
// are unset from a .env file in the working directory if one exists.
func Load() (Config, error) {
	if err := loadDotEnv(".env"); err != nil {
		return Config{}, fmt.Errorf("load .env: %w", err)
	}
	c := Config{
		Port:         env("PORT", "8080"),
		DBPath:       env("DB_PATH", "/data/app.db"),
		JWTSecret:    []byte(os.Getenv("JWT_SECRET")),
		GeminiAPIKey: os.Getenv("GEMINI_API_KEY"),
		GeminiModel:  env("GEMINI_MODEL", "gemini-flash-latest"),
	}
	for _, o := range strings.Split(env("CORS_ORIGINS", "*"), ",") {
		if o = strings.TrimSpace(o); o != "" {
			c.CORSOrigins = append(c.CORSOrigins, o)
		}
	}

	var err error
	if c.AccessTTL, err = duration("ACCESS_TTL", 15*time.Minute); err != nil {
		return c, err
	}
	if c.RefreshTTL, err = duration("REFRESH_TTL", 30*24*time.Hour); err != nil {
		return c, err
	}
	if len(c.JWTSecret) < 32 {
		return c, errors.New("JWT_SECRET must be set to at least 32 bytes (in the environment or in .env in the working directory); generate one with: openssl rand -hex 32")
	}
	return c, nil
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func duration(key string, def time.Duration) (time.Duration, error) {
	v := os.Getenv(key)
	if v == "" {
		return def, nil
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return d, nil
}
