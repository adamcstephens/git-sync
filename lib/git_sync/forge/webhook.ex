defmodule GitSync.Forge.Webhook do
  @moduledoc """
  Signature checking shared by the forges that sign their deliveries.
  """

  @doc """
  Compares a hex HMAC-SHA256 signature against one computed over the body,
  taking the first of `names` the delivery carries and expecting `prefix` in
  front of the digest.
  """
  def verify_hmac_sha256(headers, body, secret, names, prefix \\ "") do
    case Enum.find_value(names, fn name -> header(headers, name) end) do
      nil -> {:error, :missing_signature}
      signature -> compare(signature, prefix <> expected(body, secret))
    end
  end

  defp expected(body, secret),
    do: Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)

  defp compare(signature, expected) do
    if byte_size(signature) == byte_size(expected) and :crypto.hash_equals(signature, expected),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} -> String.downcase(key) == name && value end)
  end
end
