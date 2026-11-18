package dev.huseyin.notes;

import io.quarkus.panache.common.Page;
import io.quarkus.panache.common.Sort;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;

@Path("/notes")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class NoteResource {
	public record NoteRequest(@NotBlank String title, @NotBlank String body, @NotBlank String tag) {}

	@POST
	@Transactional
	public Response create(@Valid NoteRequest r) {
		Note n = new Note();
		n.title = r.title(); n.body = r.body(); n.tag = r.tag();
		n.persist();
		return Response.status(Response.Status.CREATED).entity(n).build();
	}

	@GET
	@Path("/{id}")
	public Response get(@PathParam("id") long id) {
		Note n = Note.findById(id);
		return n == null ? Response.status(Response.Status.NOT_FOUND).build() : Response.ok(n).build();
	}

	@GET
	public List<Note> byTag(@QueryParam("tag") String tag) {
		return Note.<Note>find("tag", Sort.descending("id"), tag).page(Page.ofSize(20)).list();
	}

	@GET
	@Path("/search")
	public List<Note> search(@QueryParam("q") String q) {
		return Note.<Note>find("upper(title) like upper(?1)", "%" + q + "%").page(Page.ofSize(20)).list();
	}

	@PUT
	@Path("/{id}")
	@Transactional
	public Response update(@PathParam("id") long id, @Valid NoteRequest r) {
		Note n = Note.findById(id);
		if (n == null) return Response.status(Response.Status.NOT_FOUND).build();
		n.title = r.title(); n.body = r.body(); n.tag = r.tag();
		return Response.ok(n).build();
	}

	@DELETE
	@Path("/{id}")
	@Transactional
	public Response delete(@PathParam("id") long id) {
		return Note.deleteById(id) ? Response.noContent().build() : Response.status(Response.Status.NOT_FOUND).build();
	}
}
