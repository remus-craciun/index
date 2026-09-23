-- name: CountUsers :one
SELECT COUNT(*) FROM users;

-- name: CreateUser :exec
INSERT INTO users (id, email, hashed_password, created_at)
VALUES (@id, @email, @hashed_password, @created_at);

-- name: GetUserByEmail :one
SELECT * FROM users WHERE email = @email;

-- name: GetUserByID :one
SELECT * FROM users WHERE id = @id;
