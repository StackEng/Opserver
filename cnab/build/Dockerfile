FROM cr.stackoverflow.software/so-pubplat-cnab:2024.10.16.174409-276.1@sha256:36cf26cd2d2ea251ce46edcc966174ab1ed95ccf2818cdc763ba58a384328177
    
COPY ./cnab/app /cnab/app
COPY ./charts /cnab/app/charts
RUN chmod 755 /cnab/app/run.ps1

ARG BUNDLE_VERSION
ENV BUNDLE_VERSION=${BUNDLE_VERSION}

CMD ["/cnab/app/run"]