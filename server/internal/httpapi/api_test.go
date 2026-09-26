package httpapi_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"github.com/remus-craciun/index/server/internal/ai"
	"github.com/remus-craciun/index/server/internal/auth"
	"github.com/remus-craciun/index/server/internal/db"
	"github.com/remus-craciun/index/server/internal/httpapi"
	"github.com/remus-craciun/index/server/internal/service"
)

const testSecret = "0123456789abcdef0123456789abcdef"

type fakePlanner struct {
	plan     ai.PlanDraft
	subtasks []ai.TaskDraft
	gotReq   ai.DecomposeRequest

	// revise builds the model's answer from the current plan.
	revise    func(ai.ReviseRequest) ai.PlanRevision
	gotRevise ai.ReviseRequest
}

func (f *fakePlanner) RevisePlan(_ context.Context, req ai.ReviseRequest) (ai.PlanRevision, error) {
	f.gotRevise = req
	return f.revise(req), nil
}

func (f *fakePlanner) DecomposePlan(_ context.Context, req ai.DecomposeRequest) (ai.PlanDraft, error) {
	f.gotReq = req
	p := f.plan
	return p, p.Validate()
}

func (f *fakePlanner) BreakdownTask(context.Context, ai.BreakdownRequest) ([]ai.TaskDraft, error) {
	return ai.ValidateTasks(f.subtasks)
}

type client struct {
	t     *testing.T
	base  string
	token string
}

func newServer(t *testing.T, planner ai.Planner) *client {
	t.Helper()
	store, err := db.Open(context.Background(), filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	tokens := auth.NewIssuer([]byte(testSecret), time.Minute, 0)
	svc := service.New(store, tokens, planner)
	log := slog.New(slog.NewTextHandler(testWriter{t}, nil))
	srv := httptest.NewServer(httpapi.NewRouter(svc, tokens, []string{"*"}, log))
	t.Cleanup(srv.Close)
	return &client{t: t, base: srv.URL + "/api/v1"}
}

// do sends body as JSON and decodes the response into out (if non-nil),
// failing the test unless the status matches.
func (c *client) do(method, path string, body any, wantStatus int, out any) {
	c.t.Helper()
	var r io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			c.t.Fatal(err)
		}
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, c.base+path, r)
	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != wantStatus {
		c.t.Fatalf("%s %s: status %d, want %d; body: %s", method, path, resp.StatusCode, wantStatus, raw)
	}
	if out != nil {
		if err := json.Unmarshal(raw, out); err != nil {
			c.t.Fatalf("%s %s: decode: %v; body: %s", method, path, err, raw)
		}
	}
}

func (c *client) login() {
	c.t.Helper()
	var tok auth.Tokens
	c.do("POST", "/auth/register", map[string]string{"email": "me@example.com", "password": "correct horse"}, 201, &tok)
	c.token = tok.AccessToken
}

func TestHealth(t *testing.T) {
	c := newServer(t, nil)
	var h struct{ Status, Database, Time string }
	c.do("GET", "/health", nil, 200, &h)
	if h.Status != "ok" || h.Database != "ok" || h.Time == "" {
		t.Fatalf("health: %+v", h)
	}
	root := &client{t: t, base: strings.TrimSuffix(c.base, "/api/v1")}
	root.do("GET", "/health", nil, 200, nil)
	root.do("GET", "/healthz", nil, 200, nil)
}

func TestAuthFlow(t *testing.T) {
	c := newServer(t, nil)

	var status struct {
		HasUser bool `json:"has_user"`
	}
	c.do("GET", "/auth/status", nil, 200, &status)
	if status.HasUser {
		t.Fatal("fresh db reports a user")
	}

	c.do("POST", "/auth/register", map[string]string{"email": "bad", "password": "correct horse"}, 400, nil)
	c.do("POST", "/auth/register", map[string]string{"email": "me@example.com", "password": "short"}, 400, nil)

	var tok auth.Tokens
	c.do("POST", "/auth/register", map[string]string{"email": "me@example.com", "password": "correct horse"}, 201, &tok)
	c.do("GET", "/auth/status", nil, 200, &status)
	if !status.HasUser {
		t.Fatal("status does not report the registered user")
	}
	c.do("POST", "/auth/register", map[string]string{"email": "other@example.com", "password": "correct horse"}, 403, nil)

	c.do("POST", "/auth/login", map[string]string{"email": "me@example.com", "password": "wrong password"}, 401, nil)
	c.do("POST", "/auth/login", map[string]string{"email": "nobody@example.com", "password": "correct horse"}, 401, nil)
	c.do("POST", "/auth/login", map[string]string{"email": "ME@example.com", "password": "correct horse"}, 200, &tok)

	c.do("GET", "/plans", nil, 401, nil)
	c.token = tok.RefreshToken
	c.do("GET", "/plans", nil, 401, nil) // refresh token is not an access token
	c.token = ""

	c.do("POST", "/auth/refresh", map[string]string{"refresh_token": tok.AccessToken}, 401, nil)
	var refreshed auth.Tokens
	c.do("POST", "/auth/refresh", map[string]string{"refresh_token": tok.RefreshToken}, 200, &refreshed)
	c.token = refreshed.AccessToken
	c.do("GET", "/plans", nil, 200, nil)
}

func TestCRUDAndToday(t *testing.T) {
	c := newServer(t, nil)
	c.login()

	var plan service.Plan
	c.do("POST", "/plans", map[string]any{"title": "Go", "target_date": "2026-03-01"}, 201, &plan)
	var ms service.Milestone
	c.do("POST", "/plans/"+plan.ID+"/milestones", map[string]any{"title": "Basics"}, 201, &ms)
	if ms.OrderIndex != 1 {
		t.Fatalf("order_index = %d, want 1", ms.OrderIndex)
	}

	var learn, adhoc, overdue, done, undated service.Task
	c.do("POST", "/tasks", map[string]any{"title": "Read spec", "milestone_id": ms.ID, "scheduled_date": "2026-02-10", "estimated_minutes": 30}, 201, &learn)
	c.do("POST", "/tasks", map[string]any{"title": "Buy milk", "scheduled_date": "2026-02-10"}, 201, &adhoc)
	c.do("POST", "/tasks", map[string]any{"title": "Call mom", "scheduled_date": "2026-02-08"}, 201, &overdue)
	c.do("POST", "/tasks", map[string]any{"title": "Gym", "scheduled_date": "2026-02-10", "status": "completed"}, 201, &done)
	c.do("POST", "/tasks", map[string]any{"title": "Someday"}, 201, &undated)
	c.do("POST", "/tasks", map[string]any{"title": "x", "status": "nope"}, 400, nil)
	c.do("POST", "/tasks", map[string]any{"title": "x", "milestone_id": uuid.NewString()}, 400, nil)

	var today service.Today
	c.do("GET", "/today?date=2026-02-10", nil, 200, &today)
	var got []string
	for _, it := range today.Items {
		got = append(got, it.Title)
	}
	want := []string{"Call mom", "Read spec", "Buy milk", "Gym"}
	if len(got) != len(want) {
		t.Fatalf("today = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("today = %v, want %v", got, want)
		}
	}
	if !today.Items[0].Overdue || today.Items[1].PlanTitle == nil || *today.Items[1].PlanTitle != "Go" {
		t.Fatalf("today item metadata wrong: %+v", today.Items[:2])
	}

	// PATCH: explicit null clears the date; absent fields stay unchanged.
	var patched service.Task
	c.do("PATCH", "/tasks/"+adhoc.ID, map[string]any{"scheduled_date": nil, "status": "completed"}, 200, &patched)
	if patched.ScheduledDate != nil || patched.Status != "completed" || patched.Title != "Buy milk" {
		t.Fatalf("patch result: %+v", patched)
	}

	var list struct{ Tasks []service.Task }
	c.do("GET", "/tasks?adhoc=true", nil, 200, &list)
	if len(list.Tasks) != 4 {
		t.Fatalf("adhoc tasks = %d, want 4", len(list.Tasks))
	}

	var detail service.PlanDetail
	c.do("GET", "/plans/"+plan.ID, nil, 200, &detail)
	if len(detail.Milestones) != 1 || len(detail.Milestones[0].Tasks) != 1 {
		t.Fatalf("plan detail: %+v", detail)
	}

	c.do("DELETE", "/plans/"+plan.ID, nil, 204, nil)
	c.do("GET", "/plans/"+plan.ID, nil, 404, nil)
	c.do("PATCH", "/tasks/"+learn.ID, map[string]any{"title": "x"}, 404, nil) // cascaded soft delete
	c.do("DELETE", "/plans/"+plan.ID, nil, 404, nil)
}

func TestSync(t *testing.T) {
	c := newServer(t, nil)
	c.login()

	planID, msID, taskID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	t1, t2 := "2026-01-01T10:00:00Z", "2026-01-01T11:00:00Z"

	var first service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Changes: service.Changes{
		LearningPlans: []service.Plan{{ID: planID, Title: "P", Status: "active", CreatedAt: t1, UpdatedAt: t1}},
		Milestones:    []service.Milestone{{ID: msID, PlanID: planID, Title: "M", OrderIndex: 1, Status: "active", CreatedAt: t1, UpdatedAt: t1}},
		Tasks:         []service.Task{{ID: taskID, MilestoneID: &msID, Title: "v2", Status: "pending", CreatedAt: t1, UpdatedAt: t2}},
	}}, 200, &first)
	if first.Cursor == 0 || len(first.Changes.Tasks) != 1 || first.Changes.Tasks[0].UpdatedAt != "2026-01-01T11:00:00.000Z" {
		t.Fatalf("first sync: %+v", first)
	}

	// Nothing changed since the cursor: empty pull.
	var idle service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Cursor: first.Cursor}, 200, &idle)
	if len(idle.Changes.Tasks)+len(idle.Changes.LearningPlans)+len(idle.Changes.Milestones) != 0 || idle.Cursor != first.Cursor {
		t.Fatalf("idle sync: %+v", idle)
	}

	// An older edit (10:30Z, written with a +02:00 offset) loses; the server copy
	// comes back even though it is not newer than the cursor.
	var stale service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Cursor: first.Cursor, Changes: service.Changes{
		Tasks: []service.Task{{ID: taskID, MilestoneID: &msID, Title: "v1", Status: "pending", CreatedAt: t1, UpdatedAt: "2026-01-01T12:30:00+02:00"}},
	}}, 200, &stale)
	if len(stale.Changes.Tasks) != 1 || stale.Changes.Tasks[0].Title != "v2" {
		t.Fatalf("stale push should return server copy v2: %+v", stale.Changes.Tasks)
	}

	// A newer tombstone wins and propagates.
	del := "2026-01-02T00:00:00Z"
	var tomb service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Cursor: stale.Cursor, Changes: service.Changes{
		Tasks: []service.Task{{ID: taskID, MilestoneID: &msID, Title: "v2", Status: "pending", CreatedAt: t1, UpdatedAt: del, DeletedAt: &del}},
	}}, 200, &tomb)
	if len(tomb.Changes.Tasks) != 1 || tomb.Changes.Tasks[0].DeletedAt == nil {
		t.Fatalf("tombstone not applied: %+v", tomb.Changes.Tasks)
	}

	// A second device starting from scratch sees everything, including the tombstone.
	var full service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{}, 200, &full)
	if len(full.Changes.LearningPlans) != 1 || len(full.Changes.Milestones) != 1 || len(full.Changes.Tasks) != 1 || full.Changes.Tasks[0].DeletedAt == nil {
		t.Fatalf("full sync: %+v", full.Changes)
	}

	// Server-side REST edits show up in the next pull.
	c.do("PATCH", "/plans/"+planID, map[string]any{"title": "P2"}, 200, nil)
	var afterRest service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Cursor: full.Cursor}, 200, &afterRest)
	if len(afterRest.Changes.LearningPlans) != 1 || afterRest.Changes.LearningPlans[0].Title != "P2" {
		t.Fatalf("rest edit not pulled: %+v", afterRest.Changes)
	}

	// A cursor ahead of the server forces a full reset.
	var reset service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Cursor: afterRest.Cursor + 100}, 200, &reset)
	if !reset.Reset || len(reset.Changes.LearningPlans) != 1 {
		t.Fatalf("reset sync: %+v", reset)
	}

	// Bad input is rejected atomically.
	c.do("POST", "/sync", service.SyncRequest{Changes: service.Changes{
		Tasks: []service.Task{{ID: uuid.NewString(), MilestoneID: ptr(uuid.NewString()), Title: "x", Status: "pending", CreatedAt: t1, UpdatedAt: t1}},
	}}, 400, nil)
	c.do("POST", "/sync", service.SyncRequest{Changes: service.Changes{
		Tasks: []service.Task{{ID: uuid.NewString(), Title: "x", Status: "pending", CreatedAt: "yesterday", UpdatedAt: t1}},
	}}, 400, nil)
}

func TestAIDecomposeAndBreakdown(t *testing.T) {
	fp := &fakePlanner{
		plan: ai.PlanDraft{
			Title: "Distributed Go", Description: "6 weeks",
			Milestones: []ai.MilestoneDraft{
				{Title: "Phase 2", OrderIndex: 2, Tasks: []ai.TaskDraft{{Title: "Raft", EstimatedMinutes: 60}}},
				{Title: "Phase 1", OrderIndex: 1, Tasks: []ai.TaskDraft{
					{Title: "Goroutines", EstimatedMinutes: 30}, {Title: "Channels", EstimatedMinutes: 30},
				}},
			},
		},
		subtasks: []ai.TaskDraft{{Title: "Read paper", EstimatedMinutes: 30}, {Title: "Implement", EstimatedMinutes: 30}},
	}
	c := newServer(t, fp)
	c.login()

	c.do("POST", "/ai/decompose-plan", map[string]any{"prompt": ""}, 400, nil)

	var plan service.PlanDetail
	c.do("POST", "/ai/decompose-plan", map[string]any{
		"prompt": "Learn distributed systems in Go", "start_date": "2026-03-02", "minutes_per_day": 60,
	}, 201, &plan)
	if fp.gotReq.MinutesPerDay != 60 || fp.gotReq.StartDate != "2026-03-02" || fp.gotReq.Weekdays != ai.AllWeekdays {
		t.Fatalf("planner request: %+v", fp.gotReq)
	}
	if len(plan.Milestones) != 2 || plan.Milestones[0].Title != "Phase 1" {
		t.Fatalf("milestones: %+v", plan.Milestones)
	}
	p1, p2 := plan.Milestones[0].Tasks, plan.Milestones[1].Tasks
	if *p1[0].ScheduledDate != "2026-03-02" || *p1[1].ScheduledDate != "2026-03-02" || *p2[0].ScheduledDate != "2026-03-03" {
		t.Fatalf("scheduling wrong: %s %s %s", *p1[0].ScheduledDate, *p1[1].ScheduledDate, *p2[0].ScheduledDate)
	}
	if plan.TargetDate == nil || *plan.TargetDate != "2026-03-03" {
		t.Fatalf("target date = %v, want last scheduled day", plan.TargetDate)
	}

	raft := p2[0]
	var bd struct {
		Tasks []service.Task `json:"tasks"`
	}
	c.do("POST", "/ai/breakdown-task", map[string]any{"task_id": raft.ID}, 201, &bd)
	if len(bd.Tasks) != 2 || *bd.Tasks[0].MilestoneID != *raft.MilestoneID || *bd.Tasks[0].ScheduledDate != "2026-03-03" {
		t.Fatalf("subtasks: %+v", bd.Tasks)
	}
	c.do("PATCH", "/tasks/"+raft.ID, map[string]any{"title": "x"}, 404, nil)
	c.do("POST", "/ai/breakdown-task", map[string]any{"task_id": raft.ID}, 404, nil)

	// Wednesday only: the two 30-minute tasks share 2026-03-04, Raft waits a week.
	var wed service.PlanDetail
	c.do("POST", "/ai/decompose-plan", map[string]any{
		"prompt": "Learn distributed systems in Go", "start_date": "2026-03-02", "minutes_per_day": 60, "weekdays": 4,
	}, 201, &wed)
	if fp.gotReq.Weekdays != 4 {
		t.Fatalf("weekdays not forwarded: %+v", fp.gotReq)
	}
	w1, w2 := wed.Milestones[0].Tasks, wed.Milestones[1].Tasks
	if *w1[0].ScheduledDate != "2026-03-04" || *w1[1].ScheduledDate != "2026-03-04" || *w2[0].ScheduledDate != "2026-03-11" {
		t.Fatalf("weekday scheduling wrong: %s %s %s", *w1[0].ScheduledDate, *w1[1].ScheduledDate, *w2[0].ScheduledDate)
	}
	c.do("POST", "/ai/decompose-plan", map[string]any{"prompt": "x", "weekdays": 0}, 400, nil)
}

func TestAIDisabled(t *testing.T) {
	c := newServer(t, nil)
	c.login()
	c.do("POST", "/ai/decompose-plan", map[string]any{"prompt": "x"}, 503, nil)
}

func ptr[T any](v T) *T { return &v }

// testWriter routes server logs into the test output.
type testWriter struct{ t *testing.T }

func (w testWriter) Write(p []byte) (int, error) {
	w.t.Log(string(bytes.TrimSpace(p)))
	return len(p), nil
}

func TestRecurrencesAndTaskTimes(t *testing.T) {
	c := newServer(t, nil)
	c.login()

	// Time window, reminder and completed_at via REST.
	var task service.Task
	c.do("POST", "/tasks", map[string]any{
		"title": "Standup", "scheduled_date": "2026-03-02", "start_time": "09:30", "end_time": "09:45", "reminder_minutes": 10,
	}, 201, &task)
	if task.StartTime == nil || *task.StartTime != "09:30" || task.CompletedAt != nil {
		t.Fatalf("created task: %+v", task)
	}
	c.do("POST", "/tasks", map[string]any{"title": "x", "start_time": "25:00"}, 400, nil)
	c.do("POST", "/tasks", map[string]any{"title": "x", "start_time": "10:00", "end_time": "09:00"}, 400, nil)
	c.do("POST", "/tasks", map[string]any{"title": "x", "end_time": "09:00"}, 400, nil)

	c.do("PATCH", "/tasks/"+task.ID, map[string]any{"status": "completed"}, 200, &task)
	if task.CompletedAt == nil {
		t.Fatal("completed_at not set on completion")
	}
	c.do("PATCH", "/tasks/"+task.ID, map[string]any{"status": "pending", "end_time": nil}, 200, &task)
	if task.CompletedAt != nil || task.EndTime != nil || task.StartTime == nil {
		t.Fatalf("reopen/clear end time: %+v", task)
	}

	// Recurrences sync, and occurrences reference them.
	recID, occID := uuid.NewString(), uuid.NewString()
	ts := "2026-03-01T08:00:00Z"
	var resp service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Changes: service.Changes{
		Recurrences: []service.Recurrence{{
			ID: recID, Title: "Work", Weekdays: 31, StartTime: ptr("08:00"), EndTime: ptr("17:00"),
			StartDate: "2026-03-02", Status: "active", CreatedAt: ts, UpdatedAt: ts,
		}},
		Tasks: []service.Task{{
			ID: occID, RecurrenceID: &recID, Title: "Work", ScheduledDate: ptr("2026-03-02"),
			StartTime: ptr("08:00"), EndTime: ptr("17:00"), Status: "completed", CompletedAt: ptr("2026-03-02T17:05:00+02:00"),
			CreatedAt: ts, UpdatedAt: ts,
		}},
	}}, 200, &resp)
	if len(resp.Changes.Recurrences) != 1 || resp.Changes.Recurrences[0].Weekdays != 31 {
		t.Fatalf("recurrence not synced: %+v", resp.Changes.Recurrences)
	}
	if r := resp.Changes.Recurrences[0]; r.Frequency != "weekly" || r.RepeatInterval != 1 {
		t.Fatalf("missing frequency/interval should default to weekly/1: %+v", r)
	}

	// Every 3 days round-trips.
	every3 := uuid.NewString()
	var r3 service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Cursor: resp.Cursor, Changes: service.Changes{Recurrences: []service.Recurrence{{
		ID: every3, Title: "Water plants", Frequency: "daily", RepeatInterval: 3, Weekdays: 127,
		StartDate: "2026-03-02", Status: "active", CreatedAt: ts, UpdatedAt: ts,
	}}}}, 200, &r3)
	if len(r3.Changes.Recurrences) != 1 || r3.Changes.Recurrences[0].RepeatInterval != 3 || r3.Changes.Recurrences[0].Frequency != "daily" {
		t.Fatalf("interval recurrence: %+v", r3.Changes.Recurrences)
	}
	var occ *service.Task
	for i := range resp.Changes.Tasks {
		if resp.Changes.Tasks[i].ID == occID {
			occ = &resp.Changes.Tasks[i]
		}
	}
	if occ == nil || *occ.RecurrenceID != recID || *occ.CompletedAt != "2026-03-02T15:05:00.000Z" {
		t.Fatalf("occurrence: %+v", occ)
	}

	bad := func(r service.Recurrence) {
		t.Helper()
		r.ID, r.CreatedAt, r.UpdatedAt = uuid.NewString(), ts, ts
		if r.Title == "" {
			r.Title = "x"
		}
		if r.Status == "" {
			r.Status = "active"
		}
		c.do("POST", "/sync", service.SyncRequest{Changes: service.Changes{Recurrences: []service.Recurrence{r}}}, 400, nil)
	}
	bad(service.Recurrence{Weekdays: 0, StartDate: "2026-03-02"})
	bad(service.Recurrence{Weekdays: 128, StartDate: "2026-03-02"})
	bad(service.Recurrence{Weekdays: 1, StartDate: "2026-03-02", EndDate: ptr("2026-03-01")})
	bad(service.Recurrence{Weekdays: 1, StartDate: "2026-03-02", Status: "nope"})
	bad(service.Recurrence{Weekdays: 1, StartDate: "2026-03-02", Frequency: "yearly"})
	bad(service.Recurrence{Weekdays: 127, StartDate: "2026-03-02", Frequency: "monthly"})
	bad(service.Recurrence{Weekdays: 127, StartDate: "2026-03-02", Frequency: "monthly", MonthDay: ptr[int64](32)})

	// Monthly on the 31st, every 2 months, round-trips; weekly drops month_day.
	monthly := uuid.NewString()
	var rm service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{Cursor: r3.Cursor, Changes: service.Changes{Recurrences: []service.Recurrence{
		{ID: monthly, Title: "Pay rent", Frequency: "monthly", RepeatInterval: 2, MonthDay: ptr[int64](31), Weekdays: 127,
			StartDate: "2026-01-31", Status: "active", CreatedAt: ts, UpdatedAt: ts},
		{ID: uuid.NewString(), Title: "Weekly", Frequency: "weekly", MonthDay: ptr[int64](5), Weekdays: 1,
			StartDate: "2026-01-31", Status: "active", CreatedAt: ts, UpdatedAt: ts},
	}}}, 200, &rm)
	for _, r := range rm.Changes.Recurrences {
		switch r.Title {
		case "Pay rent":
			if r.Frequency != "monthly" || r.MonthDay == nil || *r.MonthDay != 31 || r.RepeatInterval != 2 {
				t.Fatalf("monthly recurrence: %+v", r)
			}
		case "Weekly":
			if r.MonthDay != nil {
				t.Fatalf("weekly recurrence kept month_day: %+v", r)
			}
		}
	}
	bad(service.Recurrence{Weekdays: 1, StartDate: "2026-03-02", RepeatInterval: 400})

	c.do("POST", "/sync", service.SyncRequest{Changes: service.Changes{Tasks: []service.Task{{
		ID: uuid.NewString(), RecurrenceID: ptr(uuid.NewString()), Title: "orphan", Status: "pending", CreatedAt: ts, UpdatedAt: ts,
	}}}}, 400, nil)
}

func TestRevisePlan(t *testing.T) {
	fp := &fakePlanner{
		plan: ai.PlanDraft{
			Title: "Go", Description: "basics",
			Milestones: []ai.MilestoneDraft{
				{Title: "Foundations", OrderIndex: 1, Tasks: []ai.TaskDraft{
					{Title: "Syntax", EstimatedMinutes: 30}, {Title: "Types", EstimatedMinutes: 30}, {Title: "Maps", EstimatedMinutes: 30},
				}},
				{Title: "Concurrency", OrderIndex: 2, Tasks: []ai.TaskDraft{{Title: "Goroutines", EstimatedMinutes: 60}}},
			},
		},
	}
	c := newServer(t, fp)
	c.login()

	var plan service.PlanDetail
	c.do("POST", "/ai/decompose-plan", map[string]any{"prompt": "Learn Go", "start_date": "2026-03-02", "minutes_per_day": 60}, 201, &plan)
	found := plan.Milestones[0].Tasks
	syntax, types, maps := found[0], found[1], found[2]
	goroutines := plan.Milestones[1].Tasks[0]
	c.do("PATCH", "/tasks/"+syntax.ID, map[string]any{"status": "completed"}, 200, nil)

	// The model: renames Foundations, drops Types, edits Maps, adds a new
	// milestone, "forgets" the completed Syntax task, invents an ID, and
	// removes Concurrency entirely.
	fp.revise = func(req ai.ReviseRequest) ai.PlanRevision {
		f := req.Current.Milestones[0]
		return ai.PlanRevision{
			Title: "Go, faster", Description: "basics", Summary: "Trimmed foundations and added testing.",
			Milestones: []ai.RevMilestone{
				{ID: f.ID, Title: "Basics", OrderIndex: 1, Tasks: []ai.RevTask{
					{ID: maps.ID, Title: "Maps and slices", EstimatedMinutes: 45, Notes: "both"},
					{ID: "not-a-real-id", Title: "Structs", EstimatedMinutes: 30},
				}},
				{Title: "Testing", OrderIndex: 2, Tasks: []ai.RevTask{{Title: "Table tests", EstimatedMinutes: 30}}},
			},
		}
	}
	c.do("POST", "/ai/revise-plan", map[string]any{"plan_id": plan.ID, "instruction": ""}, 400, nil)
	var prop service.RevisionProposal
	c.do("POST", "/ai/revise-plan", map[string]any{"plan_id": plan.ID, "instruction": "make it faster, add testing", "today": "2026-03-05"}, 200, &prop)

	if fp.gotRevise.Today != "2026-03-05" || fp.gotRevise.MinutesPerDay != 60 {
		t.Fatalf("model request: today=%s perDay=%d", fp.gotRevise.Today, fp.gotRevise.MinutesPerDay)
	}
	statuses := map[string]string{}
	for _, ct := range fp.gotRevise.Current.Milestones[0].Tasks {
		statuses[ct.ID] = ct.Status
	}
	if statuses[syntax.ID] != "completed" || statuses[types.ID] != "pending" {
		t.Fatalf("model should see task statuses, got %v", statuses)
	}
	basics := prop.Revision.Milestones[0]
	if len(basics.Tasks) != 3 || basics.Tasks[1].ID != "" || basics.Tasks[2].ID != syntax.ID || basics.Tasks[2].Title != "Syntax" {
		t.Fatalf("reconciled Basics: %+v", basics.Tasks)
	}
	want := map[string]bool{
		"plan updated Go, faster": true, "milestone updated Basics": true, "task updated Maps and slices": true,
		"task added Structs": true, "milestone added Testing": true, "task added Table tests": true,
		"task removed Types": true, "milestone removed Concurrency": true,
	}
	for _, ch := range prop.Changes {
		key := ch.Kind + " " + ch.Action + " " + ch.Title
		if !want[key] {
			t.Errorf("unexpected change %+v", ch)
		}
		delete(want, key)
	}
	for k := range want {
		t.Errorf("missing change %q", k)
	}

	// Nothing stored yet.
	var before service.PlanDetail
	c.do("GET", "/plans/"+plan.ID, nil, 200, &before)
	if before.Title != "Go" || len(before.Milestones) != 2 {
		t.Fatalf("preview must not write: %+v", before.Plan)
	}

	var after service.PlanDetail
	c.do("POST", "/plans/"+plan.ID+"/apply-revision", map[string]any{
		"revision": prop.Revision, "start_date": "2026-03-05", "minutes_per_day": 60,
	}, 200, &after)
	if after.Title != "Go, faster" || len(after.Milestones) != 2 || after.Milestones[0].Title != "Basics" || after.Milestones[1].Title != "Testing" {
		t.Fatalf("applied plan: %+v", after)
	}
	byTitle := map[string]service.Task{}
	for _, m := range after.Milestones {
		for _, tk := range m.Tasks {
			byTitle[tk.Title] = tk
		}
	}
	if byTitle["Maps and slices"].ID != maps.ID || *byTitle["Maps and slices"].EstimatedMinutes != 45 {
		t.Fatalf("edited task kept its identity: %+v", byTitle["Maps and slices"])
	}
	if s := byTitle["Syntax"]; s.Status != "completed" || *s.ScheduledDate != *syntax.ScheduledDate {
		t.Fatalf("completed task must be untouched: %+v", s)
	}
	// Pending tasks re-spread from the start date: 45 (Maps) | 30 + 30 (Structs, Table tests).
	if *byTitle["Maps and slices"].ScheduledDate != "2026-03-05" || *byTitle["Structs"].ScheduledDate != "2026-03-06" ||
		*byTitle["Table tests"].ScheduledDate != "2026-03-06" {
		t.Fatalf("rescheduling: maps=%s structs=%s tests=%s", *byTitle["Maps and slices"].ScheduledDate,
			*byTitle["Structs"].ScheduledDate, *byTitle["Table tests"].ScheduledDate)
	}
	c.do("PATCH", "/tasks/"+types.ID, map[string]any{"title": "x"}, 404, nil)
	c.do("PATCH", "/tasks/"+goroutines.ID, map[string]any{"title": "x"}, 404, nil)

	// Removals reach other devices as tombstones.
	var pull service.SyncResponse
	c.do("POST", "/sync", service.SyncRequest{}, 200, &pull)
	deleted := map[string]bool{}
	for _, tk := range pull.Changes.Tasks {
		if tk.DeletedAt != nil {
			deleted[tk.ID] = true
		}
	}
	if !deleted[types.ID] || !deleted[goroutines.ID] {
		t.Fatalf("expected tombstones for removed tasks, got %v", deleted)
	}

	// A revision can't remove finished work even when sent directly.
	c.do("POST", "/plans/"+plan.ID+"/apply-revision", map[string]any{
		"revision": ai.PlanRevision{Title: "Go", Milestones: []ai.RevMilestone{{Title: "Only", OrderIndex: 1}}},
	}, 200, &after)
	var stillThere bool
	for _, m := range after.Milestones {
		for _, tk := range m.Tasks {
			stillThere = stillThere || tk.ID == syntax.ID
		}
	}
	if !stillThere {
		t.Fatal("completed task was removed by a revision")
	}
}

func TestSessions(t *testing.T) {
	c := newServer(t, nil)
	var phone, laptop auth.Tokens
	c.do("POST", "/auth/register", map[string]string{"email": "me@example.com", "password": "correct horse"}, 201, &phone)
	c.do("POST", "/auth/login", map[string]string{"email": "me@example.com", "password": "correct horse"}, 200, &laptop)

	// Refresh tokens carry no expiry.
	var claims jwt.RegisteredClaims
	if _, _, err := jwt.NewParser().ParseUnverified(phone.RefreshToken, &claims); err != nil || claims.ExpiresAt != nil {
		t.Fatalf("refresh token should not expire: exp=%v err=%v", claims.ExpiresAt, err)
	}

	// Refreshing keeps working, and the new refresh token works too.
	var next auth.Tokens
	c.do("POST", "/auth/refresh", map[string]string{"refresh_token": phone.RefreshToken}, 200, &next)
	c.do("POST", "/auth/refresh", map[string]string{"refresh_token": next.RefreshToken}, 200, nil)

	// Logging out the phone revokes that session only, including older
	// refresh tokens of the same session.
	c.do("POST", "/auth/logout", map[string]string{"refresh_token": next.RefreshToken}, 204, nil)
	c.do("POST", "/auth/refresh", map[string]string{"refresh_token": next.RefreshToken}, 401, nil)
	c.do("POST", "/auth/refresh", map[string]string{"refresh_token": phone.RefreshToken}, 401, nil)
	c.do("POST", "/auth/refresh", map[string]string{"refresh_token": laptop.RefreshToken}, 200, nil)

	// Logout is idempotent and tolerates junk.
	c.do("POST", "/auth/logout", map[string]string{"refresh_token": next.RefreshToken}, 204, nil)
	c.do("POST", "/auth/logout", map[string]string{"refresh_token": "garbage"}, 204, nil)

	// A refresh token from before sessions existed (no sid, 30-day expiry)
	// still refreshes and is moved onto a permanent session.
	sub := func(tok string) string {
		var rc jwt.RegisteredClaims
		jwt.NewParser().ParseUnverified(tok, &rc)
		return rc.Subject
	}
	legacy := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"typ": "refresh", "iss": "index", "sub": sub(laptop.AccessToken),
		"iat": time.Now().Unix(), "exp": time.Now().Add(30 * 24 * time.Hour).Unix(),
	})
	legacyToken, _ := legacy.SignedString([]byte(testSecret))
	var migrated auth.Tokens
	c.do("POST", "/auth/refresh", map[string]string{"refresh_token": legacyToken}, 200, &migrated)
	var mc struct {
		Sid string `json:"sid"`
		jwt.RegisteredClaims
	}
	jwt.NewParser().ParseUnverified(migrated.RefreshToken, &mc)
	if mc.Sid == "" || mc.ExpiresAt != nil {
		t.Fatalf("legacy token should move to a permanent session: sid=%q exp=%v", mc.Sid, mc.ExpiresAt)
	}
}
