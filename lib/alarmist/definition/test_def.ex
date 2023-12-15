defmodule TestDef do
  @moduledoc false

  use Alarmist.Definition

  for interface <- [VintageNetEth0, VintageNetWlan0] do
    defalarm interface do
      Something
    end
  end
end
