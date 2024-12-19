FROM crdev.stackoverflow.software/so-pubplat-cnab:2024.12.19.105621-prerelease@sha256:06e1f1006bcfc6f05d90634225af23b7e99b7faea50c967e5bd50c3cf4ce5dae
    
COPY ./cnab/app /cnab/app
COPY ./charts /cnab/app/charts

ARG BUNDLE_VERSION
ENV BUNDLE_VERSION=${BUNDLE_VERSION}

CMD ["/cnab/app/run"]