# myOolala Database Schema - Updated

## Tables

### profiles (base user data - shared across all views)
| Column | Type | Description |
|--------|------|-------------|
| id | uuid | PK, matches auth.users.id |
| handle | varchar | Unique username (3-20 chars, lowercase) |
| display_name | varchar | Full display name |
| avatar_url | text | Profile picture URL |
| citizen_id | varchar | Unique ID like `#893-17009` |
| plan | varchar | 'free', 'pro', 'lifetime' |
| contact_email | varchar | Public contact email |

### views (per-context customizable data)
| Column | Type | Description |
|--------|------|-------------|
| id | uuid | PK |
| user_id | uuid | FK → profiles.id |
| name | varchar | 'social', 'work', 'events', 'exclusive' |
| label | varchar | Custom label |
| visibility | varchar | 'public' or 'private_link' |
| permanent_token | varchar | Unique token for private links |
| bio | text | View-specific bio |
| spotlight | text | Featured content text |
| **origin_flags** | text[] | **Array of emoji flags** (origins) |
| **based_in_flags** | text[] | **Array of emoji flags** (locations) |
| **based_in_cities** | text[] | **Array of city names** |
| **based_in_airports** | text[] | **Array of airport codes** |
| based_in_flag | text | Single flag (backwards compat) |
| based_in_city | text | Single city (backwards compat) |
| based_in_airport | text | Single airport (backwards compat) |

### blocks (links per view)
| Column | Type | Description |
|--------|------|-------------|
| id | uuid | PK |
| view_id | uuid | FK → views.id |
| type | varchar | 'link', 'spotlight', etc. |
| title | varchar | Link title |
| url | text | Link URL |
| icon | varchar | Icon identifier |
| order | integer | Display order |
| data | jsonb | Additional data |

### socials (global social accounts)
| Column | Type | Description |
|--------|------|-------------|
| id | uuid | PK |
| user_id | uuid | FK → profiles.id |
| platform | varchar | 'instagram', 'spotify', etc. |
| username | varchar | Username on platform |
| url | text | Full URL |
| order | integer | Display order |

### socials_views (visibility per view)
| Column | Type | Description |
|--------|------|-------------|
| id | uuid | PK |
| social_id | uuid | FK → socials.id |
| view_id | uuid | FK → views.id |
| visible | boolean | Show on this view? |
| order | integer | Display order |

### phones / phones_views (same pattern as socials)

## Flag Display Format

**Option A (implemented):** `🇫🇷🇷🇺 → 🇦🇪🇵🇹`
- Multiple origins (left side)
- Multiple locations (right side)
- Arrow shows journey direction

## Example Queries

```sql
-- Get view with all arrays
SELECT 
    v.*,
    p.handle,
    p.display_name,
    p.citizen_id,
    p.avatar_url
FROM views v
JOIN profiles p ON v.user_id = p.id
WHERE p.handle = 'mickael' AND v.name = 'social';

-- Get blocks for a view
SELECT * FROM blocks 
WHERE view_id = 'uuid-here' 
ORDER BY "order" ASC;

-- Get visible socials for a view
SELECT s.* 
FROM socials s
JOIN socials_views sv ON s.id = sv.social_id
WHERE sv.view_id = 'uuid-here' AND sv.visible = true
ORDER BY sv."order" ASC;
```

## Common Mapping Mistakes
- ❌ `username` → ✅ `handle`
- ❌ `profile_id` → ✅ `view_id` 
- ❌ `position` → ✅ `order`
- ❌ `payload` → ✅ `data`
- ❌ Single flag → ✅ Array of flags
