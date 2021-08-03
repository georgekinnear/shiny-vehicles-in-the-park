library(tidyverse)

# the list from Tobia 2019 (Appendix A)
vehicles_list <-
  c(
    "Airplane",
    "Ambulance",
    "Automobile",
    "Baby Shoulder-Carrier",
    "Baby Stroller",
    "Bicycle",
    "Bus",
    "Canoe",
    "Car",
    "Carriage",
    "Crutches",
    "Drone",
    "Golf Cart",
    "Helicopter",
    "Horse",
    "Liferaft",
    "Moped",
    "Pogo Stick",
    "Rollerskate",
    "Skateboard",
    "Toy Car",
    "Truck",
    "Wheelchair",
    "WWII Truck",
    "Zip-line"
  ) %>% as_tibble() %>% 
  rownames_to_column()

vehicles_list %>% 
  mutate(
    yaml_snippet = str_glue(".- item-num: {rowname}\n.  item-name: {value}\n.  html: |\n.    {value}")
  ) %>% 
  select(yaml_snippet) %>% 
  deframe() %>% 
  paste0(collapse = "\n\n") %>% 
  cat(file = "vehicles.yml")

