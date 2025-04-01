-- Create web_anon role for unauthenticated access
CREATE ROLE web_anon NOLOGIN;
GRANT web_anon TO postgres; -- Grant to your database user

-- Create api schema
CREATE SCHEMA api;
GRANT USAGE ON SCHEMA api TO web_anon;

-- Set search path
SET search_path TO api, public;

-- Create messages table
CREATE TABLE messages (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add some sample data
INSERT INTO messages (content) VALUES 
(\'Hello, World!\'),
(\'¡Hola, Mundo!\'),
(\'Bonjour, Monde!\'),
(\'Hallo, Welt!\'),
(\'Ciao, Mondo!\');

-- Grant read access to web_anon role
GRANT SELECT ON messages TO web_anon;
GRANT USAGE ON SEQUENCE messages_id_seq TO web_anon;
GRANT INSERT, UPDATE, DELETE ON messages TO web_anon;

-- Create function to get all messages as HTML
CREATE OR REPLACE FUNCTION get_messages_html()
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT STRING_AGG(
        \'<tr id="message-\' || id || \'">\' ||
        \'<td>\' || id || \'</td>\' ||
        \'<td>\' || content || \'</td>\' ||
        \'<td>\' || to_char(created_at, \'YYYY-MM-DD HH24:MI:SS\') || \'</td>\' ||
        \'<td>\' ||
            \'<button class="btn-edit" \' ||
            \'hx-get="/rpc/get_edit_form_html?id=\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
            \'Edit</button> \' ||
            
            \'<button class="btn-delete" \' ||
            \'hx-delete="/messages?id=eq.\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-confirm="Are you sure you want to delete this message?">\' ||
            \'Delete</button>\' ||
        \'</td>\' ||
        \'</tr>\',
        E\'\
\'
    )
    INTO result
    FROM messages
    ORDER BY id;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_messages_html() TO web_anon;

-- Create function to get a single message row as HTML
CREATE OR REPLACE FUNCTION get_message_row_html(p_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT 
        \'<tr id="message-\' || id || \'">\' ||
        \'<td>\' || id || \'</td>\' ||
        \'<td>\' || content || \'</td>\' ||
        \'<td>\' || to_char(created_at, \'YYYY-MM-DD HH24:MI:SS\') || \'</td>\' ||
        \'<td>\' ||
            \'<button class="btn-edit" \' ||
            \'hx-get="/rpc/get_edit_form_html?id=\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
            \'Edit</button> \' ||
            
            \'<button class="btn-delete" \' ||
            \'hx-delete="/messages?id=eq.\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-confirm="Are you sure you want to delete this message?">\' ||
            \'Delete</button>\' ||
        \'</td>\' ||
        \'</tr>\'
    INTO result
    FROM messages
    WHERE id = p_id;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_message_row_html(INTEGER) TO web_anon;

-- Create function to add a new message and return HTML row
CREATE OR REPLACE FUNCTION add_message_html(p_content TEXT)
RETURNS TEXT AS $$
DECLARE
    new_id INTEGER;
BEGIN
    INSERT INTO messages (content)
    VALUES (p_content)
    RETURNING id INTO new_id;
    
    RETURN get_message_row_html(new_id);
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION add_message_html(TEXT) TO web_anon;

-- Create function to get an edit form for a message
CREATE OR REPLACE FUNCTION get_edit_form_html(p_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    v_content TEXT;
BEGIN
    SELECT content INTO v_content FROM messages WHERE id = p_id;
    
    RETURN 
        \'<tr id="message-\' || p_id || \'-edit">\' ||
        \'<td>\' || p_id || \'</td>\' ||
        \'<td colspan="2">\' ||
            \'<form \' ||
            \'hx-patch="/rpc/update_message_html" \' ||
            \'hx-target="#message-\' || p_id || \'-edit" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
                \'<input type="hidden" name="p_id" value="\' || p_id || \'">\' ||
                \'<input type="text" name="p_content" value="\' || v_content || \'" style="width: 100%">\' ||
                \'<button type="submit">Save</button> \' ||
                \'<button type="button" \' ||
                \'hx-get="/rpc/get_message_row_html?p_id=\' || p_id || \'" \' ||
                \'hx-target="#message-\' || p_id || \'-edit" \' ||
                \'hx-swap="outerHTML" \' ||
                \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
                \'Cancel</button>\' ||
            \'</form>\' ||
        \'</td>\' ||
        \'<td></td>\' ||
        \'</tr>\';
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_edit_form_html(INTEGER) TO web_anon;

-- Create function to update a message and return the HTML row
CREATE OR REPLACE FUNCTION update_message_html(p_id INTEGER, p_content TEXT)
RETURNS TEXT AS $$
BEGIN
    UPDATE messages 
    SET content = p_content
    WHERE id = p_id;
    
    RETURN get_message_row_html(p_id);
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION update_message_html(INTEGER, TEXT) TO web_anon;

-- Create function to search messages and return HTML
CREATE OR REPLACE FUNCTION search_messages_html(p_query TEXT)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT STRING_AGG(
        \'<tr id="message-\' || id || \'">\' ||
        \'<td>\' || id || \'</td>\' ||
        \'<td>\' || content || \'</td>\' ||
        \'<td>\' || to_char(created_at, \'YYYY-MM-DD HH24:MI:SS\') || \'</td>\' ||
        \'<td>\' ||
            \'<button class="btn-edit" \' ||
            \'hx-get="/rpc/get_edit_form_html?id=\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
            \'Edit</button> \' ||
            
            \'<button class="btn-delete" \' ||
            \'hx-delete="/messages?id=eq.\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-confirm="Are you sure you want to delete this message?">\' ||
            \'Delete</button>\' ||
        \'</td>\' ||
        \'</tr>\',
        E\'\
\'
    )
    INTO result
    FROM messages
    WHERE content ILIKE \'%\' || p_query || \'%\'
    ORDER BY id;
    
    RETURN COALESCE(result, \'<tr><td colspan="4">No messages found</td></tr>\');
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_messages_html(TEXT) TO web_anon;

-- Create function to get template for a full HTML page
CREATE OR REPLACE FUNCTION get_index_html()
RETURNS TEXT AS $$
BEGIN
    RETURN \'<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World - PostgREST + HTMX</title>
    <script src="https://unpkg.com/htmx.org@1.9.4"></script>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        form { margin: 20px 0; }
        input[type="text"] { padding: 8px; width: 70%; }
        button { padding: 8px 12px; background-color: #4CAF50; color: white; border: none; cursor: pointer; }
        button:hover { background-color: #45a049; }
        .btn-edit { background-color: #2196F3; }
        .btn-edit:hover { background-color: #0b7dda; }
        .btn-delete { background-color: #f44336; }
        .btn-delete:hover { background-color: #da190b; }
        .htmx-indicator { display: none; }
        .htmx-request .htmx-indicator { display: inline; }
        .htmx-request.htmx-indicator { display: inline; }
    </style>
</head>
<body>
    <h1>Hello World - PostgREST + HTMX Demo</h1>
    
    <h2>Add New Message</h2>
    <form hx-post="/rpc/add_message_html" 
          hx-target="#messages-tbody" 
          hx-swap="beforeend" 
          hx-headers=\'\'{"Accept": "text/html", "Prefer": "return=representation"}\'\'
          hx-on::after-request="this.reset()">
        <input type="text" name="p_content" placeholder="Enter your message" required>
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
           hx-headers=\'\'{"Accept": "text/html"}\'\'
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
        <tbody id="messages-tbody" hx-get="/rpc/get_messages_html" hx-trigger="load" hx-headers=\'\'{"Accept": "text/html"}\'\' hx-indicator="#loading-indicator">
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
</html>\';
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_index_html() TO web_anon;

-- Enable anon role for postgrest
COMMENT ON ROLE web_anon IS \'Role for accessing the API anonymously.\';

-- Create RLS policy for messages
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY messages_select_policy ON messages
    FOR SELECT USING (true);

CREATE POLICY messages_insert_policy ON messages
    FOR INSERT WITH CHECK (true);

CREATE POLICY messages_update_policy ON messages
    FOR UPDATE USING (true);

CREATE POLICY messages_delete_policy ON messages
    FOR DELETE USING (true);

-- Set permissions for PostgREST
GRANT USAGE ON SCHEMA api TO web_anon;
(\'Bonjour, Monde!\'),
(\'Hallo, Welt!\'),
(\'Ciao, Mondo!\');

-- Grant read access to web_anon role
GRANT SELECT ON messages TO web_anon;
GRANT USAGE ON SEQUENCE messages_id_seq TO web_anon;
GRANT INSERT, UPDATE, DELETE ON messages TO web_anon;

-- Create function to get all messages as HTML
CREATE OR REPLACE FUNCTION get_messages_html()
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT STRING_AGG(
        \'<tr id="message-\' || id || \'">\' ||
        \'<td>\' || id || \'</td>\' ||
        \'<td>\' || content || \'</td>\' ||
        \'<td>\' || to_char(created_at, \'YYYY-MM-DD HH24:MI:SS\') || \'</td>\' ||
        \'<td>\' ||
            \'<button class="btn-edit" \' ||
            \'hx-get="/rpc/get_edit_form_html?id=\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
            \'Edit</button> \' ||
            
            \'<button class="btn-delete" \' ||
            \'hx-delete="/messages?id=eq.\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-confirm="Are you sure you want to delete this message?">\' ||
            \'Delete</button>\' ||
        \'</td>\' ||
        \'</tr>\',
        E\'\
\'
    )
    INTO result
    FROM messages
    ORDER BY id;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_messages_html() TO web_anon;

-- Create function to get a single message row as HTML
CREATE OR REPLACE FUNCTION get_message_row_html(p_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT 
        \'<tr id="message-\' || id || \'">\' ||
        \'<td>\' || id || \'</td>\' ||
        \'<td>\' || content || \'</td>\' ||
        \'<td>\' || to_char(created_at, \'YYYY-MM-DD HH24:MI:SS\') || \'</td>\' ||
        \'<td>\' ||
            \'<button class="btn-edit" \' ||
            \'hx-get="/rpc/get_edit_form_html?id=\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
            \'Edit</button> \' ||
            
            \'<button class="btn-delete" \' ||
            \'hx-delete="/messages?id=eq.\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-confirm="Are you sure you want to delete this message?">\' ||
            \'Delete</button>\' ||
        \'</td>\' ||
        \'</tr>\'
    INTO result
    FROM messages
    WHERE id = p_id;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_message_row_html(INTEGER) TO web_anon;

-- Create function to add a new message and return HTML row
CREATE OR REPLACE FUNCTION add_message_html(p_content TEXT)
RETURNS TEXT AS $$
DECLARE
    new_id INTEGER;
BEGIN
    INSERT INTO messages (content)
    VALUES (p_content)
    RETURNING id INTO new_id;
    
    RETURN get_message_row_html(new_id);
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION add_message_html(TEXT) TO web_anon;

-- Create function to get an edit form for a message
CREATE OR REPLACE FUNCTION get_edit_form_html(p_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    v_content TEXT;
BEGIN
    SELECT content INTO v_content FROM messages WHERE id = p_id;
    
    RETURN 
        \'<tr id="message-\' || p_id || \'-edit">\' ||
        \'<td>\' || p_id || \'</td>\' ||
        \'<td colspan="2">\' ||
            \'<form \' ||
            \'hx-patch="/rpc/update_message_html" \' ||
            \'hx-target="#message-\' || p_id || \'-edit" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
                \'<input type="hidden" name="p_id" value="\' || p_id || \'">\' ||
                \'<input type="text" name="p_content" value="\' || v_content || \'" style="width: 100%">\' ||
                \'<button type="submit">Save</button> \' ||
                \'<button type="button" \' ||
                \'hx-get="/rpc/get_message_row_html?p_id=\' || p_id || \'" \' ||
                \'hx-target="#message-\' || p_id || \'-edit" \' ||
                \'hx-swap="outerHTML" \' ||
                \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
                \'Cancel</button>\' ||
            \'</form>\' ||
        \'</td>\' ||
        \'<td></td>\' ||
        \'</tr>\';
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_edit_form_html(INTEGER) TO web_anon;

-- Create function to update a message and return the HTML row
CREATE OR REPLACE FUNCTION update_message_html(p_id INTEGER, p_content TEXT)
RETURNS TEXT AS $$
BEGIN
    UPDATE messages 
    SET content = p_content
    WHERE id = p_id;
    
    RETURN get_message_row_html(p_id);
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION update_message_html(INTEGER, TEXT) TO web_anon;

-- Create function to search messages and return HTML
CREATE OR REPLACE FUNCTION search_messages_html(p_query TEXT)
RETURNS TEXT AS $$
DECLARE
    result TEXT;
BEGIN
    SELECT STRING_AGG(
        \'<tr id="message-\' || id || \'">\' ||
        \'<td>\' || id || \'</td>\' ||
        \'<td>\' || content || \'</td>\' ||
        \'<td>\' || to_char(created_at, \'YYYY-MM-DD HH24:MI:SS\') || \'</td>\' ||
        \'<td>\' ||
            \'<button class="btn-edit" \' ||
            \'hx-get="/rpc/get_edit_form_html?id=\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-headers=\'\'{"Accept": "text/html"}\'\'>\' ||
            \'Edit</button> \' ||
            
            \'<button class="btn-delete" \' ||
            \'hx-delete="/messages?id=eq.\' || id || \'" \' ||
            \'hx-target="#message-\' || id || \'" \' ||
            \'hx-swap="outerHTML" \' ||
            \'hx-confirm="Are you sure you want to delete this message?">\' ||
            \'Delete</button>\' ||
        \'</td>\' ||
        \'</tr>\',
        E\'\
\'
    )
    INTO result
    FROM messages
    WHERE content ILIKE \'%\' || p_query || \'%\'
    ORDER BY id;
    
    RETURN COALESCE(result, \'<tr><td colspan="4">No messages found</td></tr>\');
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_messages_html(TEXT) TO web_anon;

-- Create function to get template for a full HTML page
CREATE OR REPLACE FUNCTION get_index_html()
RETURNS TEXT AS $$
BEGIN
    RETURN \'<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World - PostgREST + HTMX</title>
    <script src="https://unpkg.com/htmx.org@1.9.4"></script>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        form { margin: 20px 0; }
        input[type="text"] { padding: 8px; width: 70%; }
        button { padding: 8px 12px; background-color: #4CAF50; color: white; border: none; cursor: pointer; }
        button:hover { background-color: #45a049; }
        .btn-edit { background-color: #2196F3; }
        .btn-edit:hover { background-color: #0b7dda; }
        .btn-delete { background-color: #f44336; }
        .btn-delete:hover { background-color: #da190b; }
        .htmx-indicator { display: none; }
        .htmx-request .htmx-indicator { display: inline; }
        .htmx-request.htmx-indicator { display: inline; }
    </style>
</head>
<body>
    <h1>Hello World - PostgREST + HTMX Demo</h1>
    
    <h2>Add New Message</h2>
    <form hx-post="/rpc/add_message_html" 
          hx-target="#messages-tbody" 
          hx-swap="beforeend" 
          hx-headers=\'\'{"Accept": "text/html", "Prefer": "return=representation"}\'\'
          hx-on::after-request="this.reset()">
        <input type="text" name="p_content" placeholder="Enter your message" required>
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
           hx-headers=\'\'{"Accept": "text/html"}\'\'
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
        <tbody id="messages-tbody" hx-get="/rpc/get_messages_html" hx-trigger="load" hx-headers=\'\'{"Accept": "text/html"}\'\' hx-indicator="#loading-indicator">
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
</html>\';
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_index_html() TO web_anon;

-- Enable anon role for postgrest
COMMENT ON ROLE web_anon IS \'Role for accessing the API anonymously.\';

-- Create RLS policy for messages
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY messages_select_policy ON messages
    FOR SELECT USING (true);

CREATE POLICY messages_insert_policy ON messages
    FOR INSERT WITH CHECK (true);

CREATE POLICY messages_update_policy ON messages
    FOR UPDATE USING (true);

CREATE POLICY messages_delete_policy ON messages
    FOR DELETE USING (true);

-- Set permissions for PostgREST
GRANT USAGE ON SCHEMA api TO web_anon;


