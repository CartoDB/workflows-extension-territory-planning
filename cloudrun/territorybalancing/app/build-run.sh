NAME="territory-balancing"
PROJECT_ID="cartobq"
REGION="us-central1"
GOOGLE_REGISTRY_URL="us-central1-docker.pkg.dev"
ARTIFACTS_REPOSITORY="territory-balancing"
DOCKER_LABEL="latest"

set -x

gcloud auth configure-docker ${GOOGLE_REGISTRY_URL}
docker buildx build --platform linux/amd64 -t ${GOOGLE_REGISTRY_URL}/${PROJECT_ID}/${ARTIFACTS_REPOSITORY}/${NAME}:${DOCKER_LABEL} -f Dockerfile .
docker push ${GOOGLE_REGISTRY_URL}/${PROJECT_ID}/${ARTIFACTS_REPOSITORY}/${NAME}:${DOCKER_LABEL}

gcloud run deploy \
    --project=${PROJECT_ID} \
    --region=${REGION} \
    --platform=managed \
    --memory=4Gi \
    --allow-unauthenticated \
    --image=${GOOGLE_REGISTRY_URL}/${PROJECT_ID}/${ARTIFACTS_REPOSITORY}/${NAME}:${DOCKER_LABEL} \
    --revision-suffix="${RANDOM}-$(date +%s)" \
    ${NAME}

set +x