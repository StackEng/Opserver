FROM crdev.stackoverflow.software/so-pubplat-cnab:2024.12.18.144537-prerelease@sha256:742931970046fe449345b9960a4c1ca1a180adcb42f7d1f958105d8c227086e4
    
COPY ./cnab/app /cnab/app
COPY ./charts /cnab/app/charts

ARG BUNDLE_VERSION
ENV BUNDLE_VERSION=${BUNDLE_VERSION}

CMD ["/cnab/app/run.ps1"]