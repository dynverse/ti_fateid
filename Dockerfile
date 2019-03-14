FROM dynverse/dynwrapr:v0.1.0

RUN R -e 'devtools::install_cran("destiny")'

RUN apt-get update && apt-get install -y libcgal-dev libglu1-mesa-dev libglu1-mesa-dev

RUN R -e 'devtools::install_cran("FateID")'

COPY definition.yml run.R example.sh /code/

ENTRYPOINT ["/code/run.R"]
