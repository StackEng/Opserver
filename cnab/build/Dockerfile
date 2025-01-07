FROM cr.stackoverflow.software/so-pubplat-cnab:2025.1.7.92116@sha256:e1c7397eaa8b5d6b11db49b1150290782675b3dfae2b886770e5a2048b2fa745
    
COPY ./cnab/app /cnab/app
COPY ./charts /cnab/app/charts

ARG BUNDLE_VERSION
ENV BUNDLE_VERSION=${BUNDLE_VERSION}

CMD ["/cnab/app/run"]