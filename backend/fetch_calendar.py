import json
import os
import os.path
import sys

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = [
    'https://www.googleapis.com/auth/calendar.readonly',
    'https://www.googleapis.com/auth/tasks',  # read + write (mark complete)
]

def authenticate():
    """Shows basic usage of the Google Calendar API.
    Prints the start and name of the next 10 events on the user's calendar.
    """
    config_dir = os.path.expanduser('~/.config/waylandar')
    cache_dir = os.path.expanduser('~/.cache/waylandar')
    
    os.makedirs(config_dir, exist_ok=True)
    os.makedirs(cache_dir, exist_ok=True)
    
    creds_path = os.path.join(config_dir, 'credentials.json')
    token_path = os.path.join(cache_dir, 'token.json')

    creds = None
    just_authenticated = False

    if os.path.exists(token_path):
        creds = Credentials.from_authorized_user_file(token_path, SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception:
                creds = None
        
        if not creds or not creds.valid:
            if not os.path.exists(creds_path):
                print(json.dumps({"error": f"Missing credentials.json at {creds_path}. Please follow the tutorial to get your API key."}))
                exit(1)

            if '--background' in sys.argv:
                print(json.dumps({"error": "Google Auth Expired.\nPlease run this in your terminal:\n\nwaylandar-auth"}))
                exit(1)

            flow = InstalledAppFlow.from_client_secrets_file(creds_path, SCOPES)
            creds = flow.run_local_server(port=0)
            just_authenticated = True

        with open(token_path, 'w') as token:
            token.write(creds.to_json())

    return creds, just_authenticated

def get_upcoming_events(creds):
    from googleapiclient.discovery import build
    import sys
    import calendar
    import datetime

    service = build('calendar', 'v3', credentials=creds)

    argv = list(sys.argv[1:])
    days_back = 1
    if '--days-back' in argv:
        idx = argv.index('--days-back')
        days_back = int(argv[idx + 1])
        del argv[idx:idx + 2]
    positional = [a for a in argv if a != '--background']

    if len(positional) == 2:
        year = int(positional[0])
        month = int(positional[1])
        start_date = datetime.datetime(year, month, 1, 0, 0, 0, tzinfo=datetime.timezone.utc)
        last_day = calendar.monthrange(year, month)[1]
        end_date = datetime.datetime(year, month, last_day, 23, 59, 59, tzinfo=datetime.timezone.utc)
    else:
        # Agenda mode: start `days_back` days before today (local) so a small,
        # de-emphasised slice of recent/ongoing events is available; the 250-event
        # cap still lands mostly on upcoming items.
        now_local = datetime.datetime.now().astimezone()
        midnight = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        start_date = midnight - datetime.timedelta(days=days_back)
        end_date = now_local + datetime.timedelta(days=31)

    timeMin = start_date.isoformat()
    timeMax = end_date.isoformat()
    
    events_result = service.events().list(
        calendarId='primary', 
        timeMin=timeMin,
        timeMax=timeMax,
        maxResults=250, 
        singleEvents=True,
        orderBy='startTime'
    ).execute()
    
    events = events_result.get('items', [])

    output = []
    for event in events:
        start = event['start'].get('dateTime', event['start'].get('date'))
        end = event['end'].get('dateTime', event['end'].get('date'))

        # Extract the user's custom reminders!
        reminders_list = []
        reminders = event.get('reminders', {})
        if reminders.get('useDefault'):
            reminders_list.append(10) # Google's standard default
        else:
            for override in reminders.get('overrides', []):
                if override.get('method') == 'popup':
                    reminders_list.append(override.get('minutes', 10))

        output.append({
            "id": event.get('id', ''),
            "title": event.get('summary', 'Busy'),
            "description": event.get('description', ''), # ADDED FULL DESCRIPTION!
            "start": start,
            "end": end,
            "link": event.get('htmlLink', ''),
            "meetLink": _meet_link(event),
            "rsvp": _rsvp_status(event),
            "reminders": reminders_list
        })

    return output

def _meet_link(event):
    """Video conferencing URL, if any: Google Meet entry point or hangoutLink."""
    conf = event.get('conferenceData', {})
    for ep in conf.get('entryPoints', []):
        if ep.get('entryPointType') == 'video' and ep.get('uri'):
            return ep['uri']
    return event.get('hangoutLink', '')

def _rsvp_status(event):
    """This user's RSVP: accepted / declined / tentative / needsAction.
    Events with no attendees are the user's own → treated as accepted."""
    attendees = event.get('attendees')
    if not attendees:
        return 'accepted'
    for a in attendees:
        if a.get('self'):
            return a.get('responseStatus', 'needsAction')
    return 'needsAction'

def _task_obj(tl, t):
    return {
        "id": t.get('id'),
        "listId": tl['id'],
        "list": tl.get('title', 'Tasks'),
        "title": t.get('title', '') or '(no title)',
        "notes": t.get('notes', ''),
        "due": t.get('due'),                # RFC3339 date (UTC midnight) or None
        "completed": t.get('completed'),    # RFC3339 timestamp or None
        "status": t.get('status', 'needsAction'),
        "link": t.get('webViewLink', ''),
    }

def _list_tasks(service, tasklist_id, **kwargs):
    items, page_token = [], None
    while True:
        resp = service.tasks().list(
            tasklist=tasklist_id, maxResults=100, pageToken=page_token, **kwargs
        ).execute()
        items.extend(resp.get('items', []))
        page_token = resp.get('nextPageToken')
        if not page_token:
            break
    return items

def get_tasks(creds, completed_days=1):
    """Open tasks from every list, plus tasks completed within the last
    `completed_days` days (0 = today only, 1 = since yesterday, ...)."""
    import datetime
    from googleapiclient.discovery import build

    service = build('tasks', 'v1', credentials=creds)

    now_local = datetime.datetime.now().astimezone()
    midnight = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    completed_min = (midnight - datetime.timedelta(days=completed_days)).isoformat()

    output = []
    tasklists = service.tasklists().list(maxResults=100).execute().get('items', [])
    for tl in tasklists:
        # Open tasks
        for t in _list_tasks(service, tl['id'], showCompleted=False, showHidden=False):
            output.append(_task_obj(tl, t))
        # Tasks completed today onward (no deep history)
        for t in _list_tasks(service, tl['id'], showCompleted=True, showHidden=True,
                             completedMin=completed_min):
            if t.get('status') == 'completed':
                output.append(_task_obj(tl, t))

    return output

def set_task_status(creds, tasklist_id, task_id, status):
    """status is 'completed' or 'needsAction'. Setting needsAction clears the
    completion timestamp (we send completed=None so Google un-completes it)."""
    from googleapiclient.discovery import build
    service = build('tasks', 'v1', credentials=creds)
    body = {"status": status}
    if status != "completed":
        body["completed"] = None
    service.tasks().patch(tasklist=tasklist_id, task=task_id, body=body).execute()
    return {"ok": True}

if __name__ == '__main__':
    creds, just_authenticated = authenticate()

    if just_authenticated:
        print("\nSuccessfully authenticated with Google!")
        print("You can now safely close this terminal and use the Waylandar widget.")
        sys.exit(0)

    if '--set-status' in sys.argv:
        i = sys.argv.index('--set-status')
        tasklist_id, task_id, status = sys.argv[i + 1], sys.argv[i + 2], sys.argv[i + 3]
        print(json.dumps(set_task_status(creds, tasklist_id, task_id, status)))
        sys.exit(0)

    if '--tasks' in sys.argv:
        completed_days = 1
        if '--completed-days' in sys.argv:
            completed_days = int(sys.argv[sys.argv.index('--completed-days') + 1])
        print(json.dumps(get_tasks(creds, completed_days), indent=2))
        sys.exit(0)

    events = get_upcoming_events(creds)
    print(json.dumps(events, indent=2))
