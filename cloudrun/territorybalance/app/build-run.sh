NAME="territory-balancing-lgarciaduarte"
PROJECT_ID="cartodb-on-gcp-datascience"
REGION="us-east1"
GOOGLE_REGISTRY_URL="us-east1-docker.pkg.dev"
ARTIFACTS_REPOSITORY="territory-balancing-lgarciaduarte"
DOCKER_LABEL="latest"
SERVICE_ACCOUNT="data-science-service-account@cartodb-on-gcp-datascience.iam.gserviceaccount.com"

set -x

gcloud auth configure-docker ${GOOGLE_REGISTRY_URL}
docker buildx build --platform linux/amd64 -t ${GOOGLE_REGISTRY_URL}/${PROJECT_ID}/${ARTIFACTS_REPOSITORY}/${NAME}:${DOCKER_LABEL} -f Dockerfile .
docker push ${GOOGLE_REGISTRY_URL}/${PROJECT_ID}/${ARTIFACTS_REPOSITORY}/${NAME}:${DOCKER_LABEL}

gcloud run deploy \
    --project=${PROJECT_ID} \
    --region=${REGION} \
    --platform=managed \
    --memory=4Gi \
    --image=${GOOGLE_REGISTRY_URL}/${PROJECT_ID}/${ARTIFACTS_REPOSITORY}/${NAME}:${DOCKER_LABEL} \
    --revision-suffix="${RANDOM}-$(date +%s)" \
    --service-account="${SERVICE_ACCOUNT}" \
    ${NAME}

set +x