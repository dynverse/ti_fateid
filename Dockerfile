FROM dynverse/dynwrap:bioc

RUN R -e 'devtools::install_cran("destiny")'

RUN apt-get update && apt-get install -y libcgal-dev libglu1-mesa-dev libglu1-mesa-dev

RUN R -e 'devtools::install_cran("FateID")'

LABEL version 0.1.5.1

ADD . /code

ENTRYPOINT Rscript /code/run.R
