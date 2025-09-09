FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

# Copy the src directory
COPY ./src ./src

EXPOSE 80

# Serve from the src directory
CMD [ "npx", "serve", "-s", "src", "-l", "80" ]
