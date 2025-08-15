# Ecto Changesets Recipe

## Introduction

Changesets are Ecto's way of filtering, casting, and validating data before it reaches the database. They provide a pipeline for transforming external data into valid Elixir data structures, ensuring data integrity and providing detailed error messages for invalid data.

## Basic Changeset

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :age, :integer
    field :active, :boolean, default: true
    
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :age, :active])  # Cast external data
    |> validate_required([:name, :email])           # Required fields
    |> validate_format(:email, ~r/@/)               # Email format validation
    |> validate_number(:age, greater_than: 0)       # Age must be positive
    |> validate_length(:name, min: 2, max: 100)     # Name length constraints
    |> unique_constraint(:email)                    # Database uniqueness
  end
end

# Usage example:
user = %MyApp.Accounts.User{}
changeset = MyApp.Accounts.User.changeset(user, %{
  name: "John Doe",
  email: "john@example.com",
  age: 25
})

# Check if valid
if changeset.valid? do
  {:ok, user} = MyApp.Repo.insert(changeset)
else
  # Handle errors
  errors = changeset.errors
end
```

## Advanced Changeset with Custom Validation

```elixir
defmodule MyApp.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :content, :string
    field :status, Ecto.Enum, values: [:draft, :published, :archived]
    field :slug, :string
    field :published_at, :naive_datetime
    field :tags, {:array, :string}
    
    belongs_to :author, MyApp.Accounts.User
    
    timestamps()
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :content, :status, :tags, :author_id])
    |> validate_required([:title, :content, :author_id])
    |> validate_length(:title, min: 5, max: 200)
    |> validate_length(:content, min: 10)
    |> validate_inclusion(:status, [:draft, :published, :archived])
    |> validate_tags()
    |> maybe_generate_slug()
    |> maybe_set_published_at()
    |> foreign_key_constraint(:author_id)
  end

  # Custom validation for tags
  defp validate_tags(changeset) do
    case get_field(changeset, :tags) do
      nil -> changeset
      tags when is_list(tags) ->
        if length(tags) > 10 do
          add_error(changeset, :tags, "cannot have more than 10 tags")
        else
          changeset
        end
      _ -> add_error(changeset, :tags, "must be a list")
    end
  end

  # Generate slug from title
  defp maybe_generate_slug(changeset) do
    case get_change(changeset, :title) do
      nil -> changeset
      title -> put_change(changeset, :slug, slugify(title))
    end
  end

  # Set published_at when status changes to published
  defp maybe_set_published_at(changeset) do
    case get_change(changeset, :status) do
      :published -> put_change(changeset, :published_at, NaiveDateTime.utc_now())
      _ -> changeset
    end
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
  end
end
```

## Conditional Changesets

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :role, :string, default: "user"
    field :confirmed_at, :naive_datetime
    
    timestamps()
  end

  # Registration changeset
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password, min: 8)
    |> validate_password_strength()
    |> unique_constraint(:email)
    |> hash_password()
  end

  # Update changeset (without password)
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end

  # Password change changeset
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8)
    |> validate_password_strength()
    |> hash_password()
  end

  # Admin role changeset
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, ["user", "admin", "moderator"])
  end

  # Confirmation changeset
  def confirm_changeset(user) do
    user
    |> change(confirmed_at: NaiveDateTime.utc_now())
  end

  defp validate_password_strength(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password ->
        if String.match?(password, ~r/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/) do
          changeset
        else
          add_error(changeset, :password, "must contain at least one uppercase letter, one lowercase letter, and one number")
        end
    end
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, hash_password_string(password))
    end
  end

  defp hash_password_string(password) do
    # Use your preferred hashing library (e.g., Bcrypt, Argon2)
    :crypto.hash(:sha256, password) |> Base.encode16()
  end
end
```

## Working with Changeset Errors

```elixir
defmodule MyApp.Utils.ChangesetHelpers do
  def format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  def get_first_error(changeset, field) do
    case changeset.errors[field] do
      {msg, _opts} -> msg
      _ -> nil
    end
  end

  def has_error?(changeset, field) do
    Keyword.has_key?(changeset.errors, field)
  end
end

# Usage:
changeset = MyApp.Accounts.User.changeset(%MyApp.Accounts.User{}, %{email: "invalid"})
errors = MyApp.Utils.ChangesetHelpers.format_errors(changeset)
# %{email: ["has invalid format"]}

first_email_error = MyApp.Utils.ChangesetHelpers.get_first_error(changeset, :email)
# "has invalid format"
```

## Changeset Composition

```elixir
defmodule MyApp.Accounts.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "profiles" do
    field :first_name, :string
    field :last_name, :string
    field :bio, :string
    field :avatar_url, :string
    field :social_links, :map
    
    belongs_to :user, MyApp.Accounts.User
    
    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> basic_changeset(attrs)
    |> validate_social_links()
  end

  def basic_changeset(profile, attrs) do
    profile
    |> cast(attrs, [:first_name, :last_name, :bio, :avatar_url, :social_links])
    |> validate_required([:first_name, :last_name])
    |> validate_length(:first_name, min: 1, max: 50)
    |> validate_length(:last_name, min: 1, max: 50)
    |> validate_length(:bio, max: 500)
    |> validate_url(:avatar_url)
  end

  def admin_changeset(profile, attrs) do
    profile
    |> changeset(attrs)
    |> cast(attrs, [:user_id])
    |> foreign_key_constraint(:user_id)
  end

  defp validate_url(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      url ->
        if String.match?(url, ~r/^https?:\/\/.+/) do
          changeset
        else
          add_error(changeset, field, "must be a valid URL")
        end
    end
  end

  defp validate_social_links(changeset) do
    case get_change(changeset, :social_links) do
      nil -> changeset
      links when is_map(links) ->
        Enum.reduce(links, changeset, fn {platform, url}, acc ->
          if String.match?(url, ~r/^https?:\/\/.+/) do
            acc
          else
            add_error(acc, :social_links, "#{platform} must be a valid URL")
          end
        end)
      _ -> add_error(changeset, :social_links, "must be a map")
    end
  end
end
```

## Tips & Best Practices

### Changeset Organization
- Create specific changeset functions for different use cases (registration, update, admin)
- Use composition to build complex changesets from simpler ones
- Keep changeset functions focused on single responsibilities

### Validation Strategy
- Use `cast/3` first to filter and type-cast incoming data
- Add `validate_required/2` early to catch missing fields
- Use database constraints with corresponding changeset constraints
- Custom validations should be private functions with descriptive names

### Error Handling
- Use `traverse_errors/2` to format error messages for display
- Provide meaningful error messages that help users fix issues
- Consider internationalization for error messages

### Performance
- Virtual fields for sensitive data that shouldn't be persisted
- Use `prepare_changes/2` for expensive operations that only run on valid changesets
- Consider using `unsafe_validate_unique/3` for better performance with eventual consistency

## References

- [Ecto Changeset Documentation](https://hexdocs.pm/ecto/Ecto.Changeset.html)
- [Phoenix Forms Guide](https://hexdocs.pm/phoenix/forms.html)
- [Ecto Validation Documentation](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-validations)
- [Phoenix Testing Forms](https://hexdocs.pm/phoenix/testing_forms.html)