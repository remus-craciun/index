// Package db opens the SQLite database, applies migrations and exposes the
// sqlc-generated queries.
package db

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"strings"

	"github.com/pressly/goose/v3"
	_ "modernc.org/sqlite"

	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
)

//go:embed migrations/*.sql
var migrations embed.FS

// Store bundles the connection pool with the generated queries.
type Store struct {
	DB *sql.DB
	*sqlcgen.Queries
}

// Open opens (creating if needed) the database at path and migrates it.
func Open(ctx context.Context, path string) (*Store, error) {
	dsn := "file:" + path +
		"?_pragma=journal_mode(WAL)" +
		"&_pragma=busy_timeout(5000)" +
		"&_pragma=foreign_keys(1)" +
		"&_pragma=synchronous(NORMAL)" +
		"&_txlock=immediate"
	sqlDB, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	// A single connection serialises writers, which keeps sync revision
	// allocation trivially consistent. Plenty for a single-user service.
	sqlDB.SetMaxOpenConns(1)
	if err := sqlDB.PingContext(ctx); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("open database: %w", err)
	}

	goose.SetBaseFS(migrations)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("sqlite3"); err != nil {
		sqlDB.Close()
		return nil, err
	}
	if err := goose.UpContext(ctx, sqlDB, "migrations"); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return &Store{DB: sqlDB, Queries: sqlcgen.New(sqlDB)}, nil
}

// Close closes the underlying pool.
func (s *Store) Close() error { return s.DB.Close() }

// InTx runs fn inside a transaction, committing on nil error.
func (s *Store) InTx(ctx context.Context, fn func(q *sqlcgen.Queries) error) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := fn(s.Queries.WithTx(tx)); err != nil {
		return err
	}
	return tx.Commit()
}

// InWriteTx is InTx for mutations of syncable rows: it allocates a new sync
// revision that fn must stamp on every row it writes.
func (s *Store) InWriteTx(ctx context.Context, fn func(q *sqlcgen.Queries, rev int64) error) error {
	return s.InTx(ctx, func(q *sqlcgen.Queries) error {
		rev, err := q.BumpRev(ctx)
		if err != nil {
			return err
		}
		return fn(q, rev)
	})
}

// IsNotFound reports whether err means no row matched.
func IsNotFound(err error) bool { return errors.Is(err, sql.ErrNoRows) }

// IsConstraint reports whether err is a SQLite constraint violation
// (foreign key, check, unique, not null).
func IsConstraint(err error) bool {
	return err != nil && strings.Contains(err.Error(), "constraint failed")
}
