class GemsRouter < YARD::Server::Router
  def docs_prefix; 'gems' end
  def list_prefix; 'list/gems' end
  def search_prefix; 'search/gems' end
end
