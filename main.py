def main(prompt: str):
    
    from dotenv import load_dotenv
    from anthropic import Anthropic
    import os

    load_dotenv()  # take environment variables from .env

    # Now you can access your API key
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    #print("API key loaded:", bool(api_key))

    client = Anthropic(api_key=api_key)

    
    message = client.messages.create(
        model="claude-3-7-sonnet-20250219",
        max_tokens=4096,
        messages=[
            {"role": "user", "content":
                """
                Generate a ready to use SQL script for an application based on PostgREST and HTMX:
                'Generate a SPA for a simple team task tracker'
                
                LLM Guide: Generating PostgREST + HTMX Applications

    Goal: Generate HTML code using HTMX attributes to interact with a PostgreSQL database exposed via a PostgREST API.

    Core Concepts:

    PostgREST: Auto-generates a REST API from a PostgreSQL database schema (tables, views, functions). Maps HTTP methods to SQL (GET->SELECT, POST->INSERT, PATCH->UPDATE, DELETE->DELETE).
    HTMX: Extends HTML with attributes (hx-*) to perform AJAX requests, swap content, and handle events directly in HTML, minimizing JavaScript.
    Key Synergy: Use HTMX attributes to call PostgREST endpoints. Prioritize having PostgREST functions return HTML snippets for HTMX to swap directly into the page.
    1. PostgREST API Endpoints

    Tables/Views:
    GET /tablename: Retrieve all rows.
    POST /tablename: Insert a new row (data in request body).
    PATCH /tablename?{filter}: Update matching rows (data in request body).
    DELETE /tablename?{filter}: Delete matching rows.
    Filtering: ?column=operator.value (e.g., ?id=eq.123, ?name=like.*Doe*). Combine with &. Use or=(filter1,filter2).
    Sorting: ?order=column.direction (e.g., ?order=created_at.desc). Multiple: ?order=city.asc,name.desc.
    Pagination:
    ?limit=N&offset=M
    Headers: Range: items=start-end (Use hx-headers='{"Range": "items=0-9"}')
    Functions (RPC):
    GET /rpc/function_name?param1=value1: Call read-only function with URL parameters.
    POST /rpc/function_name: Call function, parameters usually in JSON request body.
    Crucial: Functions returning text/html are ideal for HTMX. Use Accept: text/html header (hx-headers='{"Accept": "text/html"}').
    URL Encoding: Use percent-encoding (%20 for space, etc.) for table/column/function names or filter values with special characters.
    2. Essential HTMX Attributes

    hx-get="{api_url}": Perform GET request.
    hx-post="{api_url}": Perform POST request (often on <form>).
    hx-put="{api_url}": Perform PUT request.
    hx-patch="{api_url}": Perform PATCH request (preferred for updates).
    hx-delete="{api_url}": Perform DELETE request.
    hx-target="{css_selector}": Element to place the response into (e.g., #results, .list-item, this, closest tr).
    hx-swap="{strategy}": How to place the response:
    innerHTML (default): Replace content inside target.
    outerHTML: Replace the entire target element.
    beforeend: Append inside target.
    afterbegin: Prepend inside target.
    beforebegin: Insert before target.
    afterend: Insert after target.
    delete: Remove target.
    none: Do nothing with response content.
    hx-trigger="{event}": Event to trigger the request (e.g., click, submit, change, keyup changed delay:500ms, load, revealed).
    hx-headers='{"Header": "Value", ...}': Send custom HTTP headers (e.g., {"Accept": "text/html"}, {"Prefer": "return=representation"}).
    hx-include="{css_selector}": Include values from other elements in the request.
    hx-encoding="application/json": (On forms) Send form data as JSON body instead of form-encoded.
    3. Code Generation Patterns & Examples

    Pattern: Use PostgREST functions (/rpc/...) that return HTML snippets. Request them using hx-get and hx-headers='{"Accept": "text/html"}'.

    Example 1: Loading Initial Data (Table)

    HTML

    <div id="item-list-container">
        <button
            hx-get="/rpc/get_items_html"
            hx-target="#item-list-tbody"
            hx-swap="innerHTML"
            hx-trigger="load" hx-headers='{"Accept": "text/html"}'>
            Loading items...
        </button>
    </div>
    <table border="1">
        <thead><tr><th>ID</th><th>Name</th><th>Actions</th></tr></thead>
        <tbody id="item-list-tbody">
            </tbody>
    </table>
    Example 2: Adding an Item (Form POST to Table)

    HTML

    <form
        hx-post="/rpc/add_item_get_row_html"
        hx-target="#item-list-tbody"
        hx-swap="beforeend" hx-headers='{"Accept": "text/html", "Prefer": "return=representation"}'
        hx-on::after-request="this.reset()" >
        <label>Name: <input type="text" name="name" required></label>
        <button type="submit">Add Item</button>
        <span class="htmx-indicator">Adding...</span> </form>

    Example 3: Editing an Item (Inline Edit)

    HTML

    <button
        hx-get="/rpc/get_edit_item_form_html?id=123"
        hx-target="closest tr"
        hx-swap="outerHTML"
        hx-headers='{"Accept": "text/html"}' >
        Edit
    </button>

    </td>
    </tr> -->
    (Self-correction: The PATCH example above shows updating the /items endpoint directly. If aiming purely for HTML-over-the-wire, the PATCH could target an /rpc/update_item_get_row_html function that performs the update and returns the new <tr> HTML. The Accept header might need adjustment depending on what the endpoint returns.)

    Revised Example 3: Editing an Item (Inline Edit - HTML over the wire preferred)

    HTML

    <button
        hx-get="/rpc/get_edit_item_form_html?id=123"
        hx-target="closest tr"
        hx-swap="outerHTML"
        hx-headers='{"Accept": "text/html"}' >
        Edit
    </button>

    hx-target="closest tr"
                hx-swap="outerHTML"
                hx-headers='{"Accept": "text/html", "Prefer": "return=representation"}'
            >
                <input type="hidden" name="id" value="123"> Name: <input type="text" name="name" value="Initial Name">
                <button type="submit">Save</button>
                <button type="button" hx-get="/rpc/get_item_row_html?id=123" hx-target="closest tr" hx-swap="outerHTML" hx-headers='{"Accept": "text/html"}'>Cancel</button>
            </form>
        </td>
    </tr> -->
    Example 4: Deleting an Item

    HTML

    <button
        hx-delete="/items?id=eq.123" hx-target="closest tr"      hx-swap="outerHTML swap:1s" hx-confirm="Are you sure you want to delete item 123?" >
        Delete
    </button>

    Example 5: Active Search (Filter Data)

    HTML

    <input type="search" name="query"
        placeholder="Search items..."
        hx-get="/rpc/search_items_html" hx-trigger="keyup changed delay:500ms, search" hx-target="#item-list-tbody"
        hx-swap="innerHTML"
        hx-include="[name='query']" hx-headers='{"Accept": "text/html"}'
        hx-indicator="#search-indicator" />
    <span id="search-indicator" class="htmx-indicator"> Searching...</span>

    <table border="1">
        <thead><tr><th>ID</th><th>Name</th><th>Actions</th></tr></thead>
        <tbody id="item-list-tbody">
            </tbody>
    </table>
    4. Handling JSON (Less Ideal for HTMX UI Updates)

    If PostgREST returns JSON (default for /tablename), HTMX receives it.
    You can use JSON, but requires client-side templating (e.g., via JS or HTMX extensions like client-side-templates) to convert it to HTML before swapping.
    Recommendation: Avoid this if possible. Structure PostgREST functions to return HTML directly (Accept: text/html).
    5. Security Considerations

    Authentication: PostgREST handles auth (e.g., JWT). Configure it correctly.
    Authorization: Relies heavily on PostgreSQL Row Level Security (RLS) and Role privileges. Define roles and policies carefully in the database. GRANT appropriate permissions (SELECT, INSERT, UPDATE, DELETE) on tables/views/functions to the web user role.
    Input Validation: Validate data within PostgreSQL functions or using constraints.
    CSRF: Use standard CSRF protection methods (e.g., tokens) if your authentication method is vulnerable (like session cookies). HTMX will typically include inputs (like hidden CSRF tokens) in requests.
    Summary for LLM:

    Focus on hx-get, hx-post, hx-patch, hx-delete attributes pointing to PostgREST /tablename or /rpc/function_name URLs.
    Use hx-target and hx-swap to define UI updates.
    Strongly prefer /rpc/ functions that return HTML snippets. Use hx-headers='{"Accept": "text/html"}'.
    Construct URLs carefully, including filters (?col=op.val), sorting (?order=), and pagination (?limit=&offset=).
    Remember URL encoding for special characters.
    Use forms for POST/PATCH/PUT, potentially with hx-encoding="application/json" if needed, but HTML-returning functions are often simpler.
    Remind the user about configuring PostgreSQL security (RLS, Roles).
                
                Generate a SQL script that populates the database with the application mentioned above.
                *** Output the SQL directly into the <sql></sql> tag. ***
                
                MAKE SURE YOU WONT ESCAPE ANY STRINGS IN <sql>..</sql> TAG. Make it ready for execution on sql server.
                
                YOUR OUTPUT MUST BE IN THE FOLLOWING FORMAT:
                <reasoning>
                ...
                </reasoning>
                <sql>
                ...
                </sql>
                """
            }
        ]
    )

    # Get the content from the message
    llm_output = str(message.content[0].text)

    import re
    SQL_SCRIPT = re.search(r'<sql>(.*?)</sql>', llm_output, re.DOTALL)
    if SQL_SCRIPT:
        SQL_SCRIPT = SQL_SCRIPT.group(1)
    else:
        SQL_SCRIPT = ""

    print("CREATE DOMAIN "text/html" AS TEXT;")
    print()        
    print(SQL_SCRIPT)

if __name__ == "__main__":
    import sys
    
    # Get prompt from command line arguments
    prompt = ""
    if len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
    else:
        print("Please provide a prompt as command line argument")
        sys.exit(1)
        
    main(prompt)
