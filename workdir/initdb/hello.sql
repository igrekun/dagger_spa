-- Create a simple team task tracker database for PostgREST and HTMX
CREATE DOMAIN "text/html" AS TEXT;

-- Create extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create schema for our application
CREATE SCHEMA IF NOT EXISTS app;

-- Create basic tables
CREATE TABLE app.teams (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE app.users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    team_id INTEGER REFERENCES app.teams(id),
    is_admin BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login TIMESTAMPTZ
);

CREATE TABLE app.task_status (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    color TEXT NOT NULL, -- for UI color-coding
    sequence INTEGER NOT NULL -- for ordering
);

CREATE TABLE app.tasks (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    status_id INTEGER NOT NULL REFERENCES app.task_status(id),
    assigned_to INTEGER REFERENCES app.users(id),
    created_by INTEGER NOT NULL REFERENCES app.users(id),
    team_id INTEGER NOT NULL REFERENCES app.teams(id),
    due_date DATE,
    priority INTEGER NOT NULL DEFAULT 2, -- 1=low, 2=medium, 3=high
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE app.comments (
    id SERIAL PRIMARY KEY,
    task_id INTEGER NOT NULL REFERENCES app.tasks(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES app.users(id),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create trigger function to update updated_at timestamp
CREATE OR REPLACE FUNCTION app.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for tasks
CREATE TRIGGER set_timestamp
BEFORE UPDATE ON app.tasks
FOR EACH ROW
EXECUTE FUNCTION app.update_timestamp();

-- Insert basic task statuses
INSERT INTO app.task_status (name, color, sequence) VALUES 
('To Do', '#3498db', 1),
('In Progress', '#f39c12', 2),
('Review', '#9b59b6', 3),
('Done', '#2ecc71', 4);

-- Create Views
CREATE VIEW app.tasks_with_details AS
SELECT 
    t.id,
    t.title,
    t.description,
    ts.name AS status,
    ts.color AS status_color,
    t.priority,
    assigned.username AS assigned_to_username,
    assigned.full_name AS assigned_to_name,
    creator.username AS created_by_username,
    creator.full_name AS created_by_name,
    team.name AS team_name,
    t.due_date,
    t.created_at,
    t.updated_at
FROM 
    app.tasks t
    JOIN app.task_status ts ON t.status_id = ts.id
    JOIN app.users creator ON t.created_by = creator.id
    JOIN app.teams team ON t.team_id = team.id
    LEFT JOIN app.users assigned ON t.assigned_to = assigned.id;

-- Create auth related structures (simplified for demo)
CREATE ROLE web_anon NOLOGIN;
CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'mysecretpassword';
GRANT web_anon TO authenticator;

CREATE ROLE app_user NOLOGIN;
GRANT USAGE ON SCHEMA app TO app_user;
GRANT SELECT ON ALL TABLES IN SCHEMA app TO app_user;
GRANT INSERT, UPDATE, DELETE ON app.tasks, app.comments TO app_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO app_user;

-- Sample data
INSERT INTO app.teams (name, description) VALUES 
('Engineering', 'Software development team'),
('Marketing', 'Marketing and promotion team'),
('Support', 'Customer support team');

-- Sample users (password_hash would normally be properly hashed, using 'hash_' for demo)
INSERT INTO app.users (username, full_name, email, password_hash, team_id, is_admin) VALUES
('admin', 'System Administrator', 'admin@example.com', 'hash_adminpass', 1, TRUE),
('jsmith', 'John Smith', 'john@example.com', 'hash_johnpass', 1, FALSE),
('agarcia', 'Ana Garcia', 'ana@example.com', 'hash_anapass', 1, FALSE),
('bwilson', 'Bob Wilson', 'bob@example.com', 'hash_bobpass', 2, FALSE),
('clee', 'Charlie Lee', 'charlie@example.com', 'hash_charliepass', 3, FALSE);

-- Sample tasks
INSERT INTO app.tasks (title, description, status_id, assigned_to, created_by, team_id, due_date, priority) VALUES
('Implement login page', 'Create the user authentication interface', 1, 2, 1, 1, CURRENT_DATE + INTERVAL '7 days', 2),
('Fix navigation bug', 'The dropdown menu disappears on mobile view', 2, 3, 1, 1, CURRENT_DATE + INTERVAL '2 days', 3),
('Create marketing email', 'Design the monthly newsletter', 1, 4, 1, 2, CURRENT_DATE + INTERVAL '5 days', 2),
('Update documentation', 'Add new API endpoints to the docs', 3, 2, 3, 1, CURRENT_DATE + INTERVAL '3 days', 1),
('Respond to customer inquiry', 'Check ticket #1234 and respond', 4, 5, 1, 3, CURRENT_DATE - INTERVAL '1 day', 2);

-- Sample comments
INSERT INTO app.comments (task_id, user_id, content) VALUES
(1, 1, 'Please follow the design mockups in Figma'),
(1, 2, 'I''ll start working on this tomorrow'),
(2, 3, 'I found the issue, it''s a CSS z-index conflict'),
(4, 2, 'Documentation has been updated, please review'),
(5, 5, 'Customer has been contacted and issue resolved');

-- Create functions that return HTML for HTMX

-- Function to get all tasks in HTML format
CREATE OR REPLACE FUNCTION app.get_tasks_html()
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT STRING_AGG(
        '<tr id="task-' || t.id || '" class="task-row">
            <td>' || t.id || '</td>
            <td>' || t.title || '</td>
            <td><span class="status-badge" style="background-color: ' || t.status_color || ';">' || t.status || '</span></td>
            <td>' || COALESCE(t.assigned_to_name, 'Unassigned') || '</td>
            <td>' || CASE WHEN t.priority = 1 THEN 'Low' WHEN t.priority = 2 THEN 'Medium' ELSE 'High' END || '</td>
            <td>' || to_char(t.due_date, 'YYYY-MM-DD') || '</td>
            <td>
                <button class="btn-view" hx-get="/rpc/get_task_details_html?task_id=' || t.id || '" 
                        hx-target="#task-detail-container" hx-trigger="click">View</button>
                <button class="btn-edit" hx-get="/rpc/get_task_edit_form_html?task_id=' || t.id || '" 
                        hx-target="#task-detail-container" hx-trigger="click">Edit</button>
                <button class="btn-delete" hx-delete="/tasks?id=eq.' || t.id || '" 
                        hx-confirm="Are you sure you want to delete this task?" 
                        hx-target="#task-' || t.id || '" hx-swap="outerHTML">Delete</button>
            </td>
        </tr>',
        E'\n'
    ) INTO result
    FROM app.tasks_with_details t
    ORDER BY t.due_date, t.priority DESC;
    
    RETURN COALESCE(result, '<tr><td colspan="7">No tasks found</td></tr>');
END;
$$ LANGUAGE plpgsql;

-- Function to get tasks filtered by status
CREATE OR REPLACE FUNCTION app.get_tasks_by_status_html(status_name TEXT)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT STRING_AGG(
        '<tr id="task-' || t.id || '" class="task-row">
            <td>' || t.id || '</td>
            <td>' || t.title || '</td>
            <td><span class="status-badge" style="background-color: ' || t.status_color || ';">' || t.status || '</span></td>
            <td>' || COALESCE(t.assigned_to_name, 'Unassigned') || '</td>
            <td>' || CASE WHEN t.priority = 1 THEN 'Low' WHEN t.priority = 2 THEN 'Medium' ELSE 'High' END || '</td>
            <td>' || to_char(t.due_date, 'YYYY-MM-DD') || '</td>
            <td>
                <button class="btn-view" hx-get="/rpc/get_task_details_html?task_id=' || t.id || '" 
                        hx-target="#task-detail-container" hx-trigger="click">View</button>
                <button class="btn-edit" hx-get="/rpc/get_task_edit_form_html?task_id=' || t.id || '" 
                        hx-target="#task-detail-container" hx-trigger="click">Edit</button>
                <button class="btn-delete" hx-delete="/tasks?id=eq.' || t.id || '" 
                        hx-confirm="Are you sure you want to delete this task?" 
                        hx-target="#task-' || t.id || '" hx-swap="outerHTML">Delete</button>
            </td>
        </tr>',
        E'\n'
    ) INTO result
    FROM app.tasks_with_details t
    WHERE t.status = status_name
    ORDER BY t.due_date, t.priority DESC;
    
    RETURN COALESCE(result, '<tr><td colspan="7">No tasks found with status: ' || status_name || '</td></tr>');
END;
$$ LANGUAGE plpgsql;

-- Function to get task details HTML
CREATE OR REPLACE FUNCTION app.get_task_details_html(task_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    task_record app.tasks_with_details%ROWTYPE;
    comments_html TEXT;
    result TEXT;
BEGIN
    -- Get task details
    SELECT * INTO task_record
    FROM app.tasks_with_details
    WHERE id = task_id;
    
    IF NOT FOUND THEN
        RETURN '<div class="error-message">Task not found</div>';
    END IF;
    
    -- Get comments
    SELECT STRING_AGG(
        '<div class="comment">
            <div class="comment-header">
                <span class="comment-author">' || u.full_name || '</span>
                <span class="comment-date">' || to_char(c.created_at, 'YYYY-MM-DD HH:MI') || '</span>
            </div>
            <div class="comment-content">' || c.content || '</div>
        </div>',
        E'\n'
    ) INTO comments_html
    FROM app.comments c
    JOIN app.users u ON c.user_id = u.id
    WHERE c.task_id = task_id
    ORDER BY c.created_at;
    
    -- Construct the HTML
    result := '
    <div class="task-details">
        <h2>' || task_record.title || '</h2>
        <div class="task-metadata">
            <div class="metadata-item">
                <strong>Status:</strong> <span class="status-badge" style="background-color: ' || task_record.status_color || ';">' || task_record.status || '</span>
            </div>
            <div class="metadata-item">
                <strong>Assigned to:</strong> ' || COALESCE(task_record.assigned_to_name, 'Unassigned') || '
            </div>
            <div class="metadata-item">
                <strong>Priority:</strong> ' || CASE WHEN task_record.priority = 1 THEN 'Low' WHEN task_record.priority = 2 THEN 'Medium' ELSE 'High' END || '
            </div>
            <div class="metadata-item">
                <strong>Due Date:</strong> ' || to_char(task_record.due_date, 'YYYY-MM-DD') || '
            </div>
            <div class="metadata-item">
                <strong>Created By:</strong> ' || task_record.created_by_name || '
            </div>
            <div class="metadata-item">
                <strong>Team:</strong> ' || task_record.team_name || '
            </div>
        </div>
        
        <div class="task-description">
            <h3>Description</h3>
            <p>' || COALESCE(task_record.description, 'No description provided.') || '</p>
        </div>
        
        <div class="task-comments">
            <h3>Comments</h3>
            ' || COALESCE(comments_html, '<p>No comments yet.</p>') || '
        </div>
        
        <div class="add-comment-form">
            <h3>Add Comment</h3>
            <form hx-post="/rpc/add_comment_html" hx-target=".task-comments" hx-swap="innerHTML">
                <input type="hidden" name="task_id" value="' || task_id || '">
                <textarea name="content" placeholder="Enter your comment" required></textarea>
                <button type="submit">Add Comment</button>
            </form>
        </div>
        
        <div class="task-actions">
            <button class="btn-edit" hx-get="/rpc/get_task_edit_form_html?task_id=' || task_id || '" 
                    hx-target="#task-detail-container" hx-trigger="click">Edit Task</button>
            <button class="btn-back" hx-get="/rpc/get_tasks_html" 
                    hx-target="#tasks-table-body" hx-trigger="click">Back to List</button>
        </div>
    </div>';
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to get task edit form HTML
CREATE OR REPLACE FUNCTION app.get

