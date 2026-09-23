// Package httpapi exposes the service over JSON HTTP.
package httpapi

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

	"github.com/remus-craciun/index/server/internal/auth"
	"github.com/remus-craciun/index/server/internal/service"
)

type api struct {
	svc *service.Service
	log *slog.Logger
}

// NewRouter builds the HTTP handler for the whole API.
func NewRouter(svc *service.Service, tokens *auth.Issuer, corsOrigins []string, log *slog.Logger) http.Handler {
	a := &api{svc: svc, log: log}

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins: corsOrigins,
		AllowedMethods: []string{"GET", "POST", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders: []string{"Authorization", "Content-Type"},
		MaxAge:         300,
	}))

	r.Get("/health", a.health)
	r.Get("/healthz", a.health)

	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/health", a.health)

		r.Group(func(r chi.Router) {
			r.Use(middleware.Timeout(30 * time.Second))
			r.Get("/auth/status", a.authStatus)
			r.Post("/auth/register", a.register)
			r.Post("/auth/login", a.login)
			r.Post("/auth/refresh", a.refresh)
		})

		r.Group(func(r chi.Router) {
			r.Use(tokens.Middleware(a.unauthorized))

			r.Group(func(r chi.Router) {
				r.Use(middleware.Timeout(30 * time.Second))

				r.Get("/plans", a.listPlans)
				r.Post("/plans", a.createPlan)
				r.Get("/plans/{id}", a.getPlan)
				r.Patch("/plans/{id}", a.updatePlan)
				r.Delete("/plans/{id}", a.deletePlan)
				r.Post("/plans/{id}/milestones", a.createMilestone)
				r.Post("/plans/{id}/apply-revision", a.applyRevision)

				r.Patch("/milestones/{id}", a.updateMilestone)
				r.Delete("/milestones/{id}", a.deleteMilestone)

				r.Get("/tasks", a.listTasks)
				r.Post("/tasks", a.createTask)
				r.Patch("/tasks/{id}", a.updateTask)
				r.Delete("/tasks/{id}", a.deleteTask)

				r.Get("/today", a.today)
				r.Post("/sync", a.sync)
			})

			r.Group(func(r chi.Router) {
				r.Use(middleware.Timeout(90 * time.Second))
				r.Post("/ai/decompose-plan", a.decomposePlan)
				r.Post("/ai/breakdown-task", a.breakdownTask)
				r.Post("/ai/revise-plan", a.revisePlan)
			})
		})
	})
	return r
}
