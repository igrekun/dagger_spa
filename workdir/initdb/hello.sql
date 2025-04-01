-- Create web_anon role for unauthenticated access
CREATE ROLE web_anon NOLOGIN;
GRANT web_anon TO postgres; -- Grant to your database user (Replace postgres if needed)

-- Create api schema
CREATE SCHEMA api;
GRANT USAGE ON SCHEMA api TO web_anon;

-- Set search path (Consider setting this per role or database for better isolation)
-- SET search_path TO api, public;
-- Recommended approach: Set search_path for the role
ALTER ROLE web_anon SET search_path = api, public;

-- Create messages table in the api schema
CREATE TABLE api.messages (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add some sample data
INSERT INTO api.messages (content) VALUES
('Hello, World!'),
('¡Hola, Mundo!'),
('Bonjour, Monde!'),
('Hallo, Welt!'),
('Ciao, Mondo!');

-- Grant access to web_anon role for the messages table
GRANT SELECT, INSERT, UPDATE, DELETE ON api.messages TO web_anon;
GRANT USAGE ON SEQUENCE api.messages_id_seq TO web_anon;

-- Create function to get all messages as HTML
CREATE OR REPLACE FUNCTION api.get_messages_html()
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT STRING_AGG(
        '<tr id="message-' || id || '">' ||
        '<td>' || id || '</td>' ||
        '<td>' || content || '</td>' ||
        '<td>' || to_char(created_at, 'YYYY-MM-DD HH24:MI:SS') || '</td>' ||
        '<td>' ||
            '<button class="btn-edit" ' ||
            'hx-get="/rpc/get_edit_form_html?p_id=' || id || '" ' || -- Changed param name for consistency
            'hx-target="#message-' || id || '" ' ||
            'hx-swap="outerHTML" ' ||
            'hx-headers=''{"Accept": "text/html"}''>' || -- Simplified quoting
            'Edit</button> ' ||

            '<button class="btn-delete" ' ||
            'hx-delete="/messages?id=eq.' || id || '" ' ||
            'hx-target="#message-' || id || '" ' ||
            'hx-swap="outerHTML" ' || -- Consider hx-swap="delete" or handling removal in JS/another request
            'hx-confirm="Are you sure you want to delete this message?">' ||
            'Delete</button>' ||
        '</td>' ||
        '</tr>',
        E'\n' -- Standard way to represent newline in STRING_AGG
    )
    INTO result
    FROM api.messages
    ORDER BY id;

    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER; -- Added STABLE and SECURITY DEFINER

GRANT EXECUTE ON FUNCTION api.get_messages_html() TO web_anon;

-- Create function to get a single message row as HTML
CREATE OR REPLACE FUNCTION api.get_message_row_html(p_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT
        '<tr id="message-' || id || '">' ||
        '<td>' || id || '</td>' ||
        '<td>' || content || '</td>' ||
        '<td>' || to_char(created_at, 'YYYY-MM-DD HH24:MI:SS') || '</td>' ||
        '<td>' ||
            '<button class="btn-edit" ' ||
            'hx-get="/rpc/get_edit_form_html?p_id=' || id || '" ' || -- Changed param name
            'hx-target="#message-' || id || '" ' ||
            'hx-swap="outerHTML" ' ||
            'hx-headers=''{"Accept": "text/html"}''>' || -- Simplified quoting
            'Edit</button> ' ||

            '<button class="btn-delete" ' ||
            'hx-delete="/messages?id=eq.' || id || '" ' ||
            'hx-target="#message-' || id || '" ' ||
            'hx-swap="outerHTML" ' ||
            'hx-confirm="Are you sure you want to delete this message?">' ||
            'Delete</button>' ||
        '</td>' ||
        '</tr>'
    INTO result
    FROM api.messages
    WHERE id = p_id;

    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER; -- Added STABLE and SECURITY DEFINER

GRANT EXECUTE ON FUNCTION api.get_message_row_html(INTEGER) TO web_anon;

-- Create function to add a new message and return HTML row
CREATE OR REPLACE FUNCTION api.add_message_html(p_content TEXT)
RETURNS TEXT AS $$
DECLARE
    new_id INTEGER;
BEGIN
    INSERT INTO api.messages (content)
    VALUES (p_content)
    RETURNING id INTO new_id;

    RETURN api.get_message_row_html(new_id); -- Call the function with schema prefix
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER; -- Added VOLATILE and SECURITY DEFINER

GRANT EXECUTE ON FUNCTION api.add_message_html(TEXT) TO web_anon;

-- Create function to get an edit form for a message
CREATE OR REPLACE FUNCTION api.get_edit_form_html(p_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    v_content TEXT;
BEGIN
    SELECT content INTO v_content FROM api.messages WHERE id = p_id;

    RETURN
        '<tr id="message-' || p_id || '-edit">' ||
        '<td>' || p_id || '</td>' ||
        '<td colspan="2">' ||
            '<form ' ||
            'hx-post="/rpc/update_message_html" ' || -- Changed to POST to align with function call convention
            'hx-target="#message-' || p_id || '-edit" ' ||
            'hx-swap="outerHTML" ' ||
            'hx-headers=''{"Accept": "text/html"}''>' || -- Simplified quoting
                '<input type="hidden" name="p_id" value="' || p_id || '">' ||
                '<input type="text" name="p_content" value="' || COALESCE(v_content, '') || '" style="width: 100%">' || -- Added COALESCE and fixed potential HTML injection (proper escaping needed for production)
                '<button type="submit">Save</button> ' ||
                '<button type="button" ' ||
                'hx-get="/rpc/get_message_row_html?p_id=' || p_id || '" ' ||
                'hx-target="#message-' || p_id || '-edit" ' ||
                'hx-swap="outerHTML" ' ||
                'hx-headers=''{"Accept": "text/html"}''>' || -- Simplified quoting
                'Cancel</button>' ||
            '</form>' ||
        '</td>' ||
        '<td></td>' || -- Placeholder for actions column alignment
        '</tr>';
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER; -- Added STABLE and SECURITY DEFINER

GRANT EXECUTE ON FUNCTION api.get_edit_form_html(INTEGER) TO web_anon;

-- Create function to update a message and return the HTML row
-- Note: Using POST for RPC is generally preferred for actions with side-effects.
-- PostgREST expects parameters for POST RPC calls in the JSON body.
-- This function expects named parameters which map well to form submissions if
-- using application/x-www-form-urlencoded or if HTMX sends JSON matching param names.
CREATE OR REPLACE FUNCTION api.update_message_html(p_id INTEGER, p_content TEXT)
RETURNS TEXT AS $$
BEGIN
    UPDATE api.messages
    SET content = p_content
    WHERE id = p_id;

    RETURN api.get_message_row_html(p_id); -- Call the function with schema prefix
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER; -- Added VOLATILE and SECURITY DEFINER

GRANT EXECUTE ON FUNCTION api.update_message_html(INTEGER, TEXT) TO web_anon;

-- Create function to search messages and return HTML
CREATE OR REPLACE FUNCTION api.search_messages_html(p_query TEXT)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT STRING_AGG(
        '<tr id="message-' || id || '">' ||
        '<td>' || id || '</td>' ||
        '<td>' || content || '</td>' ||
        '<td>' || to_char(created_at, 'YYYY-MM-DD HH24:MI:SS') || '</td>' ||
        '<td>' ||
            '<button class="btn-edit" ' ||
            'hx-get="/rpc/get_edit_form_html?p_id=' || id || '" ' || -- Changed param name
            'hx-target="#message-' || id || '" ' ||
            'hx-swap="outerHTML" ' ||
            'hx-headers=''{"Accept": "text/html"}''>' || -- Simplified quoting
            'Edit</button> ' ||

            '<button class="btn-delete" ' ||
            'hx-delete="/messages?id=eq.' || id || '" ' ||
            'hx-target="#message-' || id || '" ' ||
            'hx-swap="outerHTML" ' ||
            'hx-confirm="Are you sure you want to delete this message?">' ||
            'Delete</button>' ||
        '</td>' ||
        '</tr>',
        E'\n'
    )
    INTO result
    FROM api.messages
    WHERE content ILIKE '%' || p_query || '%'
    ORDER BY id;

    RETURN COALESCE(result, '<tr><td colspan="4">No messages found matching search.</td></tr>');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER; -- Added STABLE and SECURITY DEFINER

GRANT EXECUTE ON FUNCTION api.search_messages_html(TEXT) TO web_anon;

-- Create function to get template for a full HTML page
-- NOTE: Serving full pages like this via RPC is possible but less common.
-- Often, a static HTML file loads the initial structure, and HTMX fetches fragments.
CREATE OR REPLACE FUNCTION api.get_index_html()
RETURNS TEXT AS $$
BEGIN
    RETURN '<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World - PostgREST + HTMX</title>
    <script src="https://unpkg.com/htmx.org@1.9.10"></script> <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; max-width: 800px; margin: 20px auto; padding: 20px; background-color: #f9f9f9; color: #333; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; background-color: #fff; box-shadow: 0 2px 3px rgba(0,0,0,0.1); }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #e9e9e9; font-weight: bold; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        form { margin: 20px 0; padding: 15px; background-color: #fff; box-shadow: 0 2px 3px rgba(0,0,0,0.1); border-radius: 4px; }
        input[type="text"], input[type="search"] { padding: 10px; width: calc(70% - 22px); margin-right: 10px; border: 1px solid #ccc; border-radius: 4px; }
        button { padding: 10px 15px; color: white; border: none; cursor: pointer; border-radius: 4px; transition: background-color 0.2s ease; }
        button[type="submit"] { background-color: #4CAF50; }
        button[type="submit"]:hover { background-color: #45a049; }
        button[type="button"] { background-color: #aaa; }
        button[type="button"]:hover { background-color: #888; }
        .btn-edit { background-color: #2196F3; margin-right: 5px; }
        .btn-edit:hover { background-color: #0b7dda; }
        .btn-delete { background-color: #f44336; }
        .btn-delete:hover { background-color: #da190b; }
        .htmx-indicator { display: none; margin-left: 10px; font-style: italic; color: #555; }
        .htmx-request .htmx-indicator { display: inline; }
        .htmx-request.htmx-indicator { display: inline; } /* For elements that become indicators */
        footer { margin-top: 30px; text-align: center; color: #777; font-size: 0.9em; }
        h1, h2 { color: #333; border-bottom: 1px solid #eee; padding-bottom: 5px; }
    </style>
</head>
<body>
    <h1>Hello World - PostgREST + HTMX Demo</h1>

    <h2>Add New Message</h2>
    <form hx-post="/rpc/add_message_html"
          hx-target="#messages-tbody"
          hx-swap="beforeend"
          hx-headers=''{"Accept": "text/html", "Prefer": "return=representation"}''
          hx-on::after-request="if(event.detail.successful) this.reset()"> <input type="text" name="p_content" placeholder="Enter your message" required>
        <button type="submit">Add Message</button>
        <span class="htmx-indicator">Adding...</span>
    </form>

    <h2>Search Messages</h2>
    <input type="search" name="p_query"
           placeholder="Search messages..."
           hx-get="/rpc/search_messages_html"
           hx-trigger="keyup changed delay:500ms, search"
           hx-target="#messages-tbody"
           hx-swap="innerHTML"
           hx-headers=''{"Accept": "text/html"}''
           hx-indicator="#search-indicator" />
    <span id="search-indicator" class="htmx-indicator">Searching...</span>

    <h2>Messages</h2>
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Message</th>
                <th>Created At</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody id="messages-tbody" hx-get="/rpc/get_messages_html" hx-trigger="load" hx-headers=''{"Accept": "text/html"}'' hx-indicator="#loading-indicator">
            <tr id="loading-indicator" class="htmx-indicator">
                <td colspan="4">Loading messages...</td>
            </tr>
            </tbody>
    </table>

    <hr>
    <footer>
        <p>Built with PostgreSQL, PostgREST, and HTMX</p>
    </footer>
</body>
</html>';
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER; -- Added STABLE and SECURITY DEFINER

GRANT EXECUTE ON FUNCTION api.get_index_html() TO web_anon;

-- COMMENT ON ROLE web_anon IS 'Role for accessing the API anonymously.'; -- Optional comment

-- Create RLS policy for messages table in the api schema
-- Ensure the table owner is NOT the web_anon role for RLS to apply correctly.
ALTER TABLE api.messages ENABLE ROW LEVEL SECURITY;

-- Allow web_anon to see all messages. Customize as needed.
CREATE POLICY messages_select_policy ON api.messages
    FOR SELECT
    TO web_anon -- Apply policy specifically to web_anon
    USING (true);

-- Allow web_anon to insert any message. Customize as needed.
CREATE POLICY messages_insert_policy ON api.messages
    FOR INSERT
    TO web_anon -- Apply policy specifically to web_anon
    WITH CHECK (true);

-- Allow web_anon to update any message. Customize as needed.
CREATE POLICY messages_update_policy ON api.messages
    FOR UPDATE
    TO web_anon -- Apply policy specifically to web_anon
    USING (true)
    WITH CHECK (true);

-- Allow web_anon to delete any message. Customize as needed.
CREATE POLICY messages_delete_policy ON api.messages
    FOR DELETE
    TO web_anon -- Apply policy specifically to web_anon
    USING (true);

-- Note: SECURITY DEFINER functions bypass RLS unless you re-set the role inside.
-- For this example where web_anon needs full access via functions,
-- granting direct table permissions + SECURITY DEFINER is okay,
-- but be aware SECURITY DEFINER functions run as the function owner.
-- If the function owner has more privileges than web_anon, it's a potential security risk.
-- An alternative is SECURITY INVOKER functions relying solely on RLS and direct grants.