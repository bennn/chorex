defmodule StoreBackend do
  @callback make_sandwich(any(), any()) :: any()
  def init(impl) do
    receive do
      {:config, config} ->
        ret = run_choreography(impl, config)
        send(config[:super], {:chorex_return, StoreBackend, ret})
    end
  end

  def big_chor(impl, config, sandwich_internals) do
    bread =
      receive do
        msg -> msg
      end

    with ingredient_stack <- sandwich_internals.(impl, config, nil) do
      send(config[Customer], impl.make_sandwich(bread, ingredient_stack))
    end
  end

  def pbj(_impl, _config, _input_x) do
    receive do
      {:choice, Customer, L} ->
        _wash_hands =
          receive do
            msg -> msg
          end

        ["almond_butter", "raspberry_jelly"]

      {:choice, Customer, R} ->
        ["peanut_butter", "raspberry_jelly"]
    end
  end

  def hamncheese(_impl, _config, _input_x) do
    receive do
      {:choice, Customer, L} ->
        ["ham", "tomato"]

      {:choice, Customer, R} ->
        ["ham", "swiss_cheese", "tomato"]
    end
  end

  def run_choreography(impl, config) do
    if function_exported?(impl, :run_choreography, 2) do
      impl.run_choreography(impl, config)
    else
      big_chor(impl, config, &pbj/3)
    end
  end
end
