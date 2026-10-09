defmodule GitSync.Encrypted.Binary do
  @moduledoc false

  use Ecto.Type

  defdelegate type(), to: Fields.Encrypted
  defdelegate cast(value), to: Fields.Encrypted
  defdelegate dump(value), to: Fields.Encrypted
  defdelegate embed_as(format), to: Fields.Encrypted
  defdelegate equal?(left, right), to: Fields.Encrypted

  def load(value) do
    case Fields.AES.decrypt(value) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> :error
    end
  end
end
