FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install

COPY client/package.json ./client/
RUN cd client && npm install

COPY . .

EXPOSE 3000

CMD ["npm", "run", "dev"]
