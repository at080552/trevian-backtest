FROM ruby:3.2

# 必要なシステムパッケージをインストール
RUN apt-get update -qq && \
    apt-get install -y build-essential libffi-dev cmake git

# Bundlerのインストール
RUN gem install bundler

# アプリケーションディレクトリの作成
WORKDIR /app

# アプリケーションコードのコピー
COPY . .

# Gemfileが存在する場合はbundle install
RUN bundle install || echo "Gemfileがないか、インストールに失敗しました"

# コンテナが常に起動し続けるようにする
CMD ["tail", "-f", "/dev/null"]