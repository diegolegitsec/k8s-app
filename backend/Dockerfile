FROM node:26-alpine
WORKDIR /app
COPY --chown=node:node package*.json ./
RUN npm ci --omit=dev
COPY --chown=node:node src/ ./src/
USER node
EXPOSE 3000
CMD ["node", "src/index.js"]
