package auth

import "golang.org/x/crypto/bcrypt"

// dummyHash is compared against when a login names an unknown email, so the
// response time does not reveal whether the account exists.
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("dummy-password"), bcrypt.DefaultCost)

// HashPassword returns a bcrypt hash of password.
func HashPassword(password string) (string, error) {
	h, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(h), err
}

// CheckPassword reports whether password matches hash. An empty hash is
// checked against a dummy to keep timing uniform.
func CheckPassword(hash, password string) bool {
	if hash == "" {
		bcrypt.CompareHashAndPassword(dummyHash, []byte(password))
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}
