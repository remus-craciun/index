package ai

import "google.golang.org/genai"

func ptr[T any](v T) *T { return &v }

var taskSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"title":             {Type: genai.TypeString, Description: "Concrete, actionable task title."},
		"estimated_minutes": {Type: genai.TypeInteger, Description: "Realistic time to complete.", Minimum: ptr(float64(minTaskMinutes)), Maximum: ptr(float64(maxTaskMinutes))},
		"notes":             {Type: genai.TypeString, Description: "Key points, resources or acceptance criteria."},
	},
	Required:         []string{"title", "estimated_minutes", "notes"},
	PropertyOrdering: []string{"title", "estimated_minutes", "notes"},
}

var planSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"title":       {Type: genai.TypeString, Description: "Learning plan name."},
		"description": {Type: genai.TypeString, Description: "Short summary of the plan."},
		"milestones": {
			Type:     genai.TypeArray,
			MinItems: ptr[int64](1),
			Items: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"title":       {Type: genai.TypeString},
					"order_index": {Type: genai.TypeInteger, Minimum: ptr(1.0)},
					"tasks":       {Type: genai.TypeArray, MinItems: ptr[int64](1), Items: taskSchema},
				},
				Required:         []string{"title", "order_index", "tasks"},
				PropertyOrdering: []string{"title", "order_index", "tasks"},
			},
		},
	},
	Required:         []string{"title", "description", "milestones"},
	PropertyOrdering: []string{"title", "description", "milestones"},
}

var breakdownSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"subtasks": {Type: genai.TypeArray, MinItems: ptr[int64](2), Items: taskSchema},
	},
	Required: []string{"subtasks"},
}
