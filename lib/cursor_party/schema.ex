defmodule CursorParty.Schema.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "profiles" do
    field(:name, :string)
    field(:gold, :integer)
    field(:power, :integer)
    field(:total_damage, :integer)
    # JSON
    field(:items, :map)
    # JSON
    field(:skill_cd, :map)

    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:id, :name, :gold, :power, :total_damage, :items, :skill_cd])
    |> validate_required([:id, :name])
  end
end

defmodule CursorParty.Schema.GameState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_state" do
    field(:key, :string)
    field(:value, :map)

    timestamps()
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
  end
end
