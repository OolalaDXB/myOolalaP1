# myOolala Database Schema

## Architecture

```
profiles (base, immuable)
    └── views (personnalisable par contexte)
            ├── blocks (links par view)
            └── socials_views (visibilité socials par view)
    └── socials (liste globale)
```

## Tables

### profiles
Données de base, partagées entre toutes les views.

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid, PK | matches auth.users.id |
| `handle` | text, unique | @username - **NOT "username"** |
| `display_name` | text | Nom affiché |
| `citizen_id` | text | Format `XXX-XXXXX` (ex: `893-17009`) - **IMMUABLE** |
| `avatar_url` | text | URL de l'avatar |
| `contact_email` | text | Email de contact |
| `plan` | text | 'free', 'pro', 'lifetime' |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**⚠️ Ces colonnes existent mais sont DÉPRÉCIÉES (migrées vers views) :**
- `bio` → utiliser `views.bio`
- `origin_flags` → utiliser `views.origin_flags`
- `based_in_flag` → utiliser `views.based_in_flag`
- `based_in_city` → utiliser `views.based_in_city`

---

### views
Chaque view = une version personnalisée du profil pour un contexte.

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid, PK | |
| `user_id` | uuid, FK → profiles.id | |
| `name` | text | 'social', 'work', 'dating', 'networking' |
| `label` | text | Label personnalisé |
| `visibility` | text | 'public', 'private', 'unlisted' |
| `permanent_token` | text | Token pour QR code |
| `bio` | text | Bio spécifique à cette view |
| `spotlight` | text | Contenu mis en avant |
| `origin_flags` | text[] | Array d'emoji drapeaux d'origine |
| `based_in_flag` | text | Emoji drapeau actuel |
| `based_in_city` | text | Ville actuelle |
| `based_in_airport` | text | Code aéroport (DXB, JFK...) |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

---

### blocks
Links et contenus assignés à une view.

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid, PK | |
| `view_id` | uuid, FK → views.id | **NOT "profile_id"** |
| `type` | text | 'link', 'spotlight', 'embed' |
| `title` | text | Titre du link |
| `url` | text | URL directe - **NOT inside "payload"** |
| `icon` | text | Icône/emoji |
| `order` | int | Position - **NOT "position"** |
| `data` | jsonb | Données additionnelles - **NOT "payload"** |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

---

### socials
Liste globale des réseaux sociaux de l'utilisateur.

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid, PK | |
| `user_id` | uuid, FK → profiles.id | |
| `platform` | text | 'instagram', 'twitter', 'linkedin', 'spotify', 'tiktok', 'youtube', 'whatsapp', 'website' |
| `username` | text | Username sur la plateforme |
| `url` | text | URL complète (optionnel) |
| `order` | int | Ordre d'affichage |
| `created_at` | timestamptz | |

**Contrainte unique :** `(user_id, platform)`

---

### socials_views
Table de liaison : quels socials sont visibles sur quelle view.

| Column | Type | Description |
|--------|------|-------------|
| `id` | uuid, PK | |
| `social_id` | uuid, FK → socials.id | |
| `view_id` | uuid, FK → views.id | |
| `visible` | boolean | Affiché ou masqué |
| `order` | int | Ordre spécifique à cette view |
| `created_at` | timestamptz | |

**Contrainte unique :** `(social_id, view_id)`

---

## Supabase Config

```javascript
const SUPABASE_URL = 'https://txbteobudstggbhlcsyz.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR4YnRlb2J1ZHN0Z2diaGxjc3l6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyMjQwMTMsImV4cCI6MjA4MzgwMDAxM30.gbHggS8GtVVRsrYmtHS08fppmiWDKcwemqN3Aj4PYfg';
```

---

## Routes

| Route | File | Description |
|-------|------|-------------|
| `/` | index.html | Landing page |
| `/auth` | auth.html | Sign in / Sign up |
| `/onboarding` | onboarding.html | Création profil initial |
| `/cockpit` | cockpit.html | Dashboard utilisateur |
| `/u/:handle` | u.html | Profil public dynamique |

---

## Queries Examples

### Charger une view avec ses données
```javascript
// 1. Get the view
const { data: view } = await supabase
    .from('views')
    .select('*')
    .eq('user_id', userId)
    .eq('name', 'social')
    .single();

// 2. Get blocks for this view
const { data: blocks } = await supabase
    .from('blocks')
    .select('*')
    .eq('view_id', view.id)
    .order('order', { ascending: true });

// 3. Get visible socials for this view
const { data: socials } = await supabase
    .from('socials_views')
    .select(`
        visible,
        order,
        socials (
            id,
            platform,
            username,
            url
        )
    `)
    .eq('view_id', view.id)
    .eq('visible', true)
    .order('order', { ascending: true });
```

### Sauvegarder les socials d'une view
```javascript
// Toggle visibility
await supabase
    .from('socials_views')
    .upsert({
        social_id: socialId,
        view_id: viewId,
        visible: true,
        order: 0
    }, { onConflict: 'social_id,view_id' });
```

---

## Common Mistakes to Avoid

| ❌ Wrong | ✅ Correct |
|----------|-----------|
| `username` | `handle` |
| `profile_id` | `view_id` (via views table) |
| `position` | `order` |
| `payload` | `data` (or direct `url` field) |
| `country_origin` | `origin_flags[]` |
| `country_location` | `based_in_flag` |
| `profile.bio` | `views.bio` (per-view) |
| `profile.socials` (JSON) | separate `socials` + `socials_views` tables |
| `##893-17009` | `893-17009` (pas de # dans citizen_id) |

---

## Citizen ID Format

- **Stockage DB :** `893-17009` (sans #)
- **Affichage UI :** `#893-17009` (avec # préfixé)
- **Format :** `XXX-XXXXX` où XXX = séquence, XXXXX = identifiant unique
- **Immuable** une fois créé

---

## Views disponibles

| Name | Usage |
|------|-------|
| `social` | Profil social (Instagram, amis) |
| `work` | Profil professionnel (LinkedIn, collègues) |
| `dating` | Profil rencontre |
| `networking` | Events, conférences |

Chaque utilisateur peut avoir plusieurs views avec des contenus différents.
