# Phoenix LiveView Uploads Recipe

## Introduction

Phoenix LiveView provides built-in support for file uploads with real-time progress tracking, drag-and-drop functionality, and client-side validation. LiveView handles the complexity of file uploads while providing a smooth user experience without requiring custom JavaScript.

## Basic File Upload

```elixir
defmodule MyAppWeb.UploadLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:uploaded_files, [])
      |> allow_upload(:avatar,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 5_000_000  # 5MB
      )
    
    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        filename = "#{entry.uuid}.#{ext(entry)}"
        dest_path = Path.join([:code.priv_dir(:my_app), "static", "uploads", filename])
        
        File.cp!(path, dest_path)
        
        # Save to database
        {:ok, file} = MyApp.Files.create_file(%{
          name: entry.client_name,
          path: "/uploads/#{filename}",
          size: entry.client_size,
          content_type: entry.client_type
        })
        
        file
      end)
    
    socket =
      socket
      |> update(:uploaded_files, &(&1 ++ uploaded_files))
      |> put_flash(:info, "Files uploaded successfully!")
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  defp ext(entry) do
    [ext | _] = entry.client_name |> String.split(".") |> Enum.reverse()
    ext
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="upload-container">
      <h1>Upload Avatar</h1>
      
      <form phx-change="validate" phx-submit="save">
        <div class="upload-area" phx-drop-target={@uploads.avatar.ref}>
          <.live_file_input upload={@uploads.avatar} />
          <p>Drag and drop files here or click to select</p>
        </div>
        
        <!-- Upload Progress -->
        <%= for entry <- @uploads.avatar.entries do %>
          <div class="upload-entry">
            <div class="filename"><%= entry.client_name %></div>
            <div class="progress-bar">
              <div class="progress-fill" style={"width: #{entry.progress}%"}></div>
            </div>
            <div class="upload-actions">
              <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref}>
                Cancel
              </button>
            </div>
          </div>
        <% end %>
        
        <!-- Upload Errors -->
        <%= for error <- upload_errors(@uploads.avatar) do %>
          <div class="error">
            <%= error_to_string(error) %>
          </div>
        <% end %>
        
        <button type="submit" disabled={!Enum.empty?(@uploads.avatar.entries)}>
          Upload
        </button>
      </form>
      
      <!-- Uploaded Files -->
      <div class="uploaded-files">
        <h2>Uploaded Files</h2>
        <%= for file <- @uploaded_files do %>
          <div class="file-item">
            <img src={file.path} alt={file.name} width="100" />
            <span><%= file.name %></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 5MB)"
  defp error_to_string(:too_many_files), do: "Too many files selected"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
```

## Multiple File Upload with Validation

```elixir
defmodule MyAppWeb.DocumentUploadLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:uploaded_documents, [])
      |> allow_upload(:documents,
        accept: ~w(.pdf .doc .docx .txt),
        max_entries: 5,
        max_file_size: 10_000_000,  # 10MB
        external: &presign_upload/2
      )
    
    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    # Custom validation logic
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    # Process uploaded documents
    uploaded_documents =
      consume_uploaded_entries(socket, :documents, fn meta, entry ->
        # Save metadata to database
        {:ok, document} = MyApp.Documents.create_document(%{
          name: entry.client_name,
          size: entry.client_size,
          content_type: entry.client_type,
          storage_key: meta.key,
          user_id: socket.assigns.current_user.id
        })
        
        # Optional: Start background processing
        MyApp.DocumentProcessor.process_async(document)
        
        document
      end)
    
    socket =
      socket
      |> update(:uploaded_documents, &(&1 ++ uploaded_documents))
      |> put_flash(:info, "#{length(uploaded_documents)} documents uploaded!")
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("remove_document", %{"id" => id}, socket) do
    document = MyApp.Documents.get_document!(id)
    
    case MyApp.Documents.delete_document(document) do
      {:ok, _} ->
        documents = Enum.reject(socket.assigns.uploaded_documents, &(&1.id == document.id))
        
        socket =
          socket
          |> assign(:uploaded_documents, documents)
          |> put_flash(:info, "Document removed")
        
        {:noreply, socket}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove document")}
    end
  end

  # External upload configuration (for cloud storage)
  defp presign_upload(entry, socket) do
    uploads_dir = "uploads/#{socket.assigns.current_user.id}"
    key = "#{uploads_dir}/#{entry.uuid}.#{ext(entry)}"
    
    config = %{
      region: "us-east-1",
      bucket: "my-app-uploads",
      key: key,
      expires_in: 3600
    }
    
    {:ok, %{uploader: "S3", key: key, url: presigned_url(config)}, socket}
  end

  defp presigned_url(config) do
    # Generate presigned URL for S3 upload
    # This would use your preferred S3 client library
    "https://#{config.bucket}.s3.amazonaws.com/#{config.key}?presigned=true"
  end

  defp ext(entry) do
    [ext | _] = entry.client_name |> String.split(".") |> Enum.reverse()
    ext
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="document-upload">
      <h1>Upload Documents</h1>
      
      <form phx-change="validate" phx-submit="save">
        <div class="upload-zone" phx-drop-target={@uploads.documents.ref}>
          <.live_file_input upload={@uploads.documents} />
          <div class="upload-instructions">
            <p>Drop files here or click to browse</p>
            <p class="upload-specs">
              Accepted: PDF, DOC, DOCX, TXT | Max size: 10MB | Max files: 5
            </p>
          </div>
        </div>
        
        <!-- Upload Preview -->
        <div class="upload-preview">
          <%= for entry <- @uploads.documents.entries do %>
            <div class="upload-item">
              <div class="file-info">
                <div class="filename"><%= entry.client_name %></div>
                <div class="file-size"><%= format_bytes(entry.client_size) %></div>
              </div>
              
              <div class="upload-progress">
                <div class="progress-bar">
                  <div class="progress-fill" style={"width: #{entry.progress}%"}></div>
                </div>
                <span class="progress-text"><%= entry.progress %>%</span>
              </div>
              
              <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref}>
                ×
              </button>
              
              <!-- Entry-specific errors -->
              <%= for error <- upload_errors(@uploads.documents, entry) do %>
                <div class="entry-error">
                  <%= error_to_string(error) %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
        
        <!-- Global upload errors -->
        <%= for error <- upload_errors(@uploads.documents) do %>
          <div class="global-error">
            <%= error_to_string(error) %>
          </div>
        <% end %>
        
        <button 
          type="submit" 
          disabled={Enum.empty?(@uploads.documents.entries) || !uploads_valid?(@uploads.documents)}
        >
          Upload Documents
        </button>
      </form>
      
      <!-- Uploaded Documents List -->
      <div class="uploaded-documents">
        <h2>Your Documents</h2>
        <%= for document <- @uploaded_documents do %>
          <div class="document-item">
            <div class="document-icon">
              <%= document_icon(document.content_type) %>
            </div>
            <div class="document-info">
              <div class="document-name"><%= document.name %></div>
              <div class="document-meta">
                <%= format_bytes(document.size) %> • 
                <%= Calendar.strftime(document.inserted_at, "%b %d, %Y") %>
              </div>
            </div>
            <div class="document-actions">
              <button phx-click="remove_document" phx-value-id={document.id}>
                Remove
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_bytes(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)}MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)}KB"
      true -> "#{bytes}B"
    end
  end

  defp document_icon(content_type) do
    case content_type do
      "application/pdf" -> "📄"
      "application/msword" -> "📝"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> "📝"
      "text/plain" -> "📄"
      _ -> "📎"
    end
  end

  defp uploads_valid?(upload) do
    Enum.all?(upload.entries, fn entry -> 
      Enum.empty?(upload_errors(upload, entry))
    end)
  end

  defp error_to_string(:too_large), do: "File is too large"
  defp error_to_string(:too_many_files), do: "Too many files selected"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
```

## Image Upload with Preview and Cropping

```elixir
defmodule MyAppWeb.ImageUploadLive do
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:uploaded_images, [])
      |> assign(:preview_image, nil)
      |> allow_upload(:images,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 10,
        max_file_size: 5_000_000,
        auto_upload: true
      )
    
    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    uploaded_images =
      consume_uploaded_entries(socket, :images, fn %{path: path}, entry ->
        # Generate unique filename
        filename = "#{entry.uuid}.#{ext(entry)}"
        upload_dir = Path.join([:code.priv_dir(:my_app), "static", "uploads"])
        File.mkdir_p!(upload_dir)
        
        dest_path = Path.join(upload_dir, filename)
        
        # Copy and process image
        File.cp!(path, dest_path)
        
        # Create thumbnails
        create_thumbnails(dest_path, filename)
        
        # Save to database
        {:ok, image} = MyApp.Images.create_image(%{
          name: entry.client_name,
          filename: filename,
          path: "/uploads/#{filename}",
          thumbnail_path: "/uploads/thumbnails/#{filename}",
          size: entry.client_size,
          content_type: entry.client_type,
          user_id: socket.assigns.current_user.id
        })
        
        image
      end)
    
    socket =
      socket
      |> update(:uploaded_images, &(&1 ++ uploaded_images))
      |> put_flash(:info, "Images uploaded successfully!")
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("preview_image", %{"id" => id}, socket) do
    image = Enum.find(socket.assigns.uploaded_images, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :preview_image, image)}
  end

  @impl true
  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :preview_image, nil)}
  end

  @impl true
  def handle_event("delete_image", %{"id" => id}, socket) do
    image = MyApp.Images.get_image!(id)
    
    case MyApp.Images.delete_image(image) do
      {:ok, _} ->
        # Delete physical files
        File.rm(Path.join([:code.priv_dir(:my_app), "static", image.path]))
        File.rm(Path.join([:code.priv_dir(:my_app), "static", image.thumbnail_path]))
        
        images = Enum.reject(socket.assigns.uploaded_images, &(&1.id == image.id))
        
        socket =
          socket
          |> assign(:uploaded_images, images)
          |> put_flash(:info, "Image deleted")
        
        {:noreply, socket}
      
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete image")}
    end
  end

  defp create_thumbnails(source_path, filename) do
    thumbnail_dir = Path.join([:code.priv_dir(:my_app), "static", "uploads", "thumbnails"])
    File.mkdir_p!(thumbnail_dir)
    
    thumbnail_path = Path.join(thumbnail_dir, filename)
    
    # Use ImageMagick or similar to create thumbnail
    # This is a simplified example
    System.cmd("convert", [
      source_path,
      "-resize", "200x200>",
      "-quality", "85",
      thumbnail_path
    ])
  end

  defp ext(entry) do
    [ext | _] = entry.client_name |> String.split(".") |> Enum.reverse()
    ext
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="image-upload">
      <h1>Upload Images</h1>
      
      <form phx-change="validate" phx-submit="save">
        <div class="upload-dropzone" phx-drop-target={@uploads.images.ref}>
          <.live_file_input upload={@uploads.images} />
          <div class="dropzone-content">
            <div class="upload-icon">📸</div>
            <p>Drop images here or click to browse</p>
            <p class="upload-specs">JPG, PNG, GIF, WebP • Max 5MB each</p>
          </div>
        </div>
        
        <!-- Upload Progress -->
        <%= for entry <- @uploads.images.entries do %>
          <div class="upload-entry">
            <div class="entry-thumbnail">
              <.live_img_preview entry={entry} width="60" height="60" />
            </div>
            <div class="entry-info">
              <div class="entry-name"><%= entry.client_name %></div>
              <div class="entry-size"><%= format_bytes(entry.client_size) %></div>
            </div>
            <div class="entry-progress">
              <div class="progress-bar">
                <div class="progress-fill" style={"width: #{entry.progress}%"}></div>
              </div>
            </div>
            <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref}>
              ×
            </button>
          </div>
        <% end %>
        
        <!-- Upload errors -->
        <%= for error <- upload_errors(@uploads.images) do %>
          <div class="upload-error">
            <%= error_to_string(error) %>
          </div>
        <% end %>
      </form>
      
      <!-- Image Gallery -->
      <div class="image-gallery">
        <h2>Your Images</h2>
        <div class="gallery-grid">
          <%= for image <- @uploaded_images do %>
            <div class="gallery-item">
              <img 
                src={image.thumbnail_path} 
                alt={image.name}
                phx-click="preview_image"
                phx-value-id={image.id}
              />
              <div class="gallery-item-actions">
                <button phx-click="delete_image" phx-value-id={image.id}>
                  Delete
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Image Preview Modal -->
      <%= if @preview_image do %>
        <div class="image-modal" phx-click="close_preview">
          <div class="modal-content" phx-click-away="close_preview">
            <img src={@preview_image.path} alt={@preview_image.name} />
            <div class="modal-info">
              <h3><%= @preview_image.name %></h3>
              <p><%= format_bytes(@preview_image.size) %></p>
            </div>
            <button phx-click="close_preview">×</button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_bytes(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)}MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)}KB"
      true -> "#{bytes}B"
    end
  end

  defp error_to_string(:too_large), do: "File is too large (max 5MB)"
  defp error_to_string(:too_many_files), do: "Too many files selected"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
```

## Tips & Best Practices

### Upload Configuration
- Set appropriate `max_file_size` limits to prevent server overload
- Use `max_entries` to limit simultaneous uploads
- Configure `accept` to restrict file types for security
- Use `auto_upload: true` for immediate processing

### File Storage
- Store files outside the web root for security
- Use cloud storage (S3, GCS) for production applications
- Generate unique filenames to prevent conflicts
- Create thumbnails for image uploads

### Validation and Security
- Always validate file types server-side
- Scan uploaded files for malware
- Implement file size limits
- Use presigned URLs for direct cloud uploads

### User Experience
- Show upload progress with visual feedback
- Provide clear error messages
- Support drag-and-drop for better UX
- Allow cancellation of uploads

### Performance
- Use `external: true` for large files or high-volume uploads
- Implement background processing for file operations
- Use CDN for serving uploaded files
- Clean up temporary files after processing

## References

- [Phoenix LiveView Uploads](https://hexdocs.pm/phoenix_live_view/uploads.html)
- [Phoenix.LiveView.Upload](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Upload.html)
- [File Upload Security](https://owasp.org/www-community/vulnerabilities/Unrestricted_File_Upload)
- [AWS S3 Integration](https://hexdocs.pm/ex_aws_s3/ExAws.S3.html)